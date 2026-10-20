// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import CryptoKit
import Foundation
import Security

struct ReleaseValidationError: LocalizedError {
  let errorDescription: String?
  init(_ message: String) {
    errorDescription = message
  }
}

func require(_ condition: Bool, _ message: String) throws {
  if !condition {
    throw ReleaseValidationError(message)
  }
}

func run(_ executable: String, _ arguments: [String]) throws -> String {
  let process = Process()
  let output = Pipe()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.standardOutput = output
  process.standardError = output
  try process.run()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  let text = String(decoding: data, as: UTF8.self)
  try require(process.terminationStatus == 0, "\(executable) failed: \(text.prefix(1000))")
  return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func validateLibraryValidation(app: URL) throws {
  var code: SecStaticCode?
  let status = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
  guard status == errSecSuccess, let code else {
    throw ReleaseValidationError("Unable to inspect release code signature: \(status)")
  }
  var information: CFDictionary?
  let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
  let informationStatus = SecCodeCopySigningInformation(code, flags, &information)
  guard informationStatus == errSecSuccess,
        let signature = information as? [String: Any],
        let rawFlags = signature[kSecCodeInfoFlags as String] as? NSNumber
  else {
    throw ReleaseValidationError("Unable to read release signing information")
  }
  let signatureFlags = SecCodeSignatureFlags(rawValue: rawFlags.uint32Value)
  if signatureFlags.contains([.adhoc, .runtime]) {
    let entitlements = signature[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
    try require(
      entitlements["com.apple.security.cs.disable-library-validation"] as? Bool == true,
      "Ad-hoc hardened runtime requires the library validation exception to load Sparkle",
    )
  }
}

func validate(directory: URL, expectedCommit: String) throws {
  let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Imaxe/Info.plist")
  let sourceInfo = try PropertyListSerialization.propertyList(
    from: Data(contentsOf: source),
    format: nil,
  ) as? [String: Any] ?? [:]
  let manifestData = try Data(contentsOf: directory.appendingPathComponent("release.json"))
  let manifest = try JSONDecoder().decode([String: String].self, from: manifestData)
  let version = manifest["version"] ?? ""
  let build = manifest["build"] ?? ""
  try require(
    version.range(of: #"^[0-9]+(\.[0-9]+)*$"#, options: .regularExpression) != nil,
    "Invalid release version",
  )
  try require(
    build.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
    "Invalid release build",
  )
  try require(
    expectedCommit.count == 40 && manifest["commit"] == expectedCommit,
    "Release commit does not match the requested commit",
  )
  try require(
    manifest["publicEDKey"] == sourceInfo["SUPublicEDKey"] as? String,
    "Release key does not match the source public key",
  )
  try require(
    manifest["feedURL"] == sourceInfo["SUFeedURL"] as? String,
    "Release feed does not match the source configuration",
  )

  let zipName = "Imaxe-\(version).zip"
  let notesName = "Imaxe-\(version).md"
  let names = [zipName, "release.json"]
  let checksums = try String(
    contentsOf: directory.appendingPathComponent("SHA256SUMS.txt"),
    encoding: .utf8,
  ).split(separator: "\n")
  try require(checksums.count == names.count, "Incomplete checksum manifest")
  for name in names {
    let data = try Data(contentsOf: directory.appendingPathComponent(name), options: .mappedIfSafe)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    try require(
      checksums.filter { $0 == "\(digest)  \(name)" }.count == 1,
      "Checksum mismatch for \(name)",
    )
  }

  guard let appcastXML = manifest["appcastXML"] else {
    throw ReleaseValidationError("Missing embedded appcast in release manifest")
  }
  let localAppcast = directory.appendingPathComponent("appcast.xml")
  if FileManager.default.fileExists(atPath: localAppcast.path) {
    let localXML = try String(contentsOf: localAppcast, encoding: .utf8)
    try require(localXML == appcastXML, "Local appcast differs from release manifest")
  }
  let document = try XMLDocument(xmlString: appcastXML, options: .nodeLoadExternalEntitiesNever)
  let items = try document.nodes(forXPath: "/rss/channel/item").compactMap { $0 as? XMLElement }
  try require(items.count == 1, "Expected one stable full-package update")
  guard let item = items.first else { throw ReleaseValidationError("Missing update item") }
  let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
  func value(_ name: String) -> String? {
    item.elements(forLocalName: name, uri: namespace).first?.stringValue
  }
  try require(
    value("version") == build && value("shortVersionString") == version,
    "Appcast version does not match the release",
  )
  try require(
    value("minimumSystemVersion") == manifest["minimumSystemVersion"],
    "Appcast minimum system version does not match the app",
  )
  guard let enclosure = item.elements(forName: "enclosure").first,
        let signatureText = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?
          .stringValue,
        let signature = Data(base64Encoded: signatureText),
        let keyText = sourceInfo["SUPublicEDKey"] as? String,
        let keyData = Data(base64Encoded: keyText)
  else { throw ReleaseValidationError("Missing EdDSA signature or public key") }
  let archive = directory.appendingPathComponent(zipName)
  let archiveData = try Data(contentsOf: archive, options: .mappedIfSafe)
  let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
  try require(key.isValidSignature(signature, for: archiveData), "Invalid update signature")
  try require(
    enclosure.attribute(forName: "length")?.stringValue == String(archiveData.count),
    "Appcast archive length does not match the ZIP",
  )
  let download = "https://github.com/eureka-0/Imaxe/releases/download/v\(version)/\(zipName)"
  try require(
    enclosure.attribute(forName: "url")?.stringValue == download,
    "Appcast download URL does not match the immutable release asset",
  )
  try require(
    enclosure.attribute(forName: "type")?.stringValue == "application/octet-stream",
    "Unexpected update archive content type",
  )
  try require(value("hardwareRequirements") == "arm64", "Appcast hardware requirements mismatch")
  let notesURL = "https://github.com/eureka-0/Imaxe/releases/tag/v\(version)"
  try require(value("fullReleaseNotesLink") == notesURL, "Appcast release notes URL mismatch")
  try require(value("releaseNotesLink") == nil, "Release notes must not depend on a Markdown asset")
  guard let description = item.elements(forName: "description").first,
        description.attribute(forLocalName: "format", uri: namespace)?.stringValue == "markdown",
        let text = description.stringValue
  else { throw ReleaseValidationError("Missing embedded Markdown release notes") }
  let notes = text.trimmingCharacters(in: .whitespacesAndNewlines)
  try require(
    notes.components(separatedBy: .newlines).first == "# Imaxe \(version)",
    "Release notes must use the marketing version without a build number",
  )
  let localNotes = directory.appendingPathComponent(notesName)
  if FileManager.default.fileExists(atPath: localNotes.path) {
    let localText = try String(contentsOf: localNotes, encoding: .utf8)
    try require(
      localText.trimmingCharacters(in: .whitespacesAndNewlines) == notes,
      "Release notes differ from the embedded appcast",
    )
  }

  let temporary = FileManager.default.temporaryDirectory
    .appendingPathComponent("imaxe-release-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: temporary) }
  _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, temporary.path])
  let app = temporary.appendingPathComponent("Imaxe.app")
  let info = try PropertyListSerialization.propertyList(
    from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
    format: nil,
  ) as? [String: Any] ?? [:]
  for (property, expected) in [
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "CFBundleIdentifier": "com.imaxe.Imaxe",
    "LSMinimumSystemVersion": manifest["minimumSystemVersion"] ?? "",
    "SUFeedURL": manifest["feedURL"] ?? "",
    "SUPublicEDKey": keyText,
  ] {
    try require(info[property] as? String == expected, "Archive \(property) mismatch")
  }
  let architectures = try run(
    "/usr/bin/lipo",
    ["-archs", app.appendingPathComponent("Contents/MacOS/Imaxe").path],
  )
  try require(architectures == "arm64", "Expected an Apple Silicon release")
  _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
  try validateLibraryValidation(app: app)
}

do {
  let arguments = CommandLine.arguments
  try require(
    arguments.count == 3,
    "usage: swift Scripts/validate-release.swift <directory> <commit>",
  )
  try validate(directory: URL(fileURLWithPath: arguments[1]), expectedCommit: arguments[2])
  print(
    "Release checksums, EdDSA signature, appcast, app bundle and library validation policy verified.",
  )
} catch {
  FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
