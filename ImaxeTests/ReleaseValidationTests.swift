// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import CryptoKit
import Foundation
@testable import Imaxe
import Testing

@Suite("Release Validation")
struct ReleaseValidationTests {
  @Test func `release verifier rejects changed bytes signatures metadata and provenance`(
  ) async throws {
    let fixture = try await Task.detached { try ReleaseFixture() }.value
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let valid = try await fixture.verify()
    #expect(valid.status == 0, "\(valid.output)")

    let zip = fixture.artifacts.appending(path: "Imaxe-1.2.3.zip")
    let originalZIP = try Data(contentsOf: zip)
    var changedZIP = originalZIP
    changedZIP.append(0)
    try changedZIP.write(to: zip)
    try fixture.checksums()
    let signature = try await fixture.verify()
    #expect(signature.status != 0 && signature.output.contains("Invalid update signature"))
    try originalZIP.write(to: zip)
    try fixture.checksums()

    let notes = fixture.artifacts.appending(path: "Imaxe-1.2.3.md")
    try "Changed after signing".write(to: notes, atomically: true, encoding: .utf8)
    let checksum = try await fixture.verify()
    #expect(checksum.status != 0 && checksum.output.contains("Checksum mismatch"))
    try fixture.checksums()

    let appcast = fixture.artifacts.appending(path: "appcast.xml")
    let originalXML = try String(contentsOf: appcast, encoding: .utf8)
    try originalXML.replacingOccurrences(of: "/download/v1.2.3/", with: "/download/latest/")
      .write(to: appcast, atomically: true, encoding: .utf8)
    try fixture.checksums()
    let url = try await fixture.verify()
    #expect(url.status != 0 && url.output.contains("download URL"))
    try originalXML.write(to: appcast, atomically: true, encoding: .utf8)
    try fixture.checksums()

    let commit = try await fixture.verify(commit: String(repeating: "b", count: 40))
    #expect(commit.status != 0 && commit.output.contains("commit"))

    let manifestURL = fixture.artifacts.appending(path: "release.json")
    let originalManifest = try Data(contentsOf: manifestURL)
    var manifest = try JSONDecoder().decode([String: String].self, from: originalManifest)
    manifest["publicEDKey"] = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
      .base64EncodedString()
    try JSONEncoder().encode(manifest).write(to: manifestURL)
    try fixture.checksums()
    let key = try await fixture.verify()
    #expect(key.status != 0 && key.output.contains("source public key"))
    try originalManifest.write(to: manifestURL)

    try originalXML.replacingOccurrences(of: "<sparkle:version>12", with: "<sparkle:version>13")
      .write(to: appcast, atomically: true, encoding: .utf8)
    try fixture.checksums()
    let version = try await fixture.verify()
    #expect(version.status != 0 && version.output.contains("Appcast version"))
  }
}

private nonisolated struct ReleaseFixture: Sendable {
  let root: URL
  let artifacts: URL
  let verifier: URL
  let commit = String(repeating: "a", count: 40)

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appending(path: "imaxe-release-validation-\(UUID().uuidString)")
    artifacts = root.appending(path: "artifacts")
    verifier = root.appending(path: "validate-release")
    let manager = FileManager.default
    for name in ["artifacts", "Scripts", "Imaxe", "Imaxe.app/Contents/MacOS"] {
      try manager.createDirectory(at: root.appending(path: name), withIntermediateDirectories: true)
    }
    let key = Curve25519.Signing.PrivateKey()
    let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    let feed = "https://eureka-0.github.io/Imaxe/appcast.xml"
    let info: [String: Any] = [
      "CFBundleIdentifier": "com.imaxe.Imaxe",
      "CFBundleName": "Imaxe",
      "CFBundleExecutable": "Imaxe",
      "CFBundlePackageType": "APPL",
      "CFBundleShortVersionString": "1.2.3",
      "CFBundleVersion": "12",
      "LSMinimumSystemVersion": "15.6",
      "SUFeedURL": feed,
      "SUPublicEDKey": publicKey,
    ]
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: root.appending(path: "Imaxe/Info.plist"))
    try plist.write(to: root.appending(path: "Imaxe.app/Contents/Info.plist"))
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent()
    try manager.copyItem(
      at: project.appending(path: "Scripts/validate-release.swift"),
      to: root.appending(path: "Scripts/validate-release.swift"),
    )
    try "int main(void) { return 0; }".write(
      to: root.appending(path: "main.c"),
      atomically: true,
      encoding: .utf8,
    )
    let compileArguments = [
      "clang",
      "-target",
      "arm64-apple-macos15.6",
      root.appending(path: "main.c").path,
      "-o",
      root.appending(path: "Imaxe.app/Contents/MacOS/Imaxe").path,
    ]
    try Self.succeed("/usr/bin/xcrun", compileArguments)
    try Self.succeed("/usr/bin/codesign", ["--sign", "-", root.appending(path: "Imaxe.app").path])
    let zip = artifacts.appending(path: "Imaxe-1.2.3.zip")
    try Self.succeed(
      "/usr/bin/ditto",
      ["-c", "-k", "--keepParent", root.appending(path: "Imaxe.app").path, zip.path],
    )
    let data = try Data(contentsOf: zip)
    let signature = try key.signature(for: data).base64EncodedString()
    let downloadURL = "https://github.com/eureka-0/Imaxe/releases/download/v1.2.3/Imaxe-1.2.3.zip"
    let notesURL = downloadURL.replacingOccurrences(of: ".zip", with: ".md")
    let xml = """
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel><item>
        <sparkle:version>12</sparkle:version>
        <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>15.6</sparkle:minimumSystemVersion>
        <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
        <sparkle:releaseNotesLink>\(notesURL)</sparkle:releaseNotesLink>
        <enclosure url="\(downloadURL)"
          length="\(data.count)" type="application/octet-stream" sparkle:edSignature="\(signature)"/>
      </item></channel>
    </rss>
    """
    try xml.write(to: artifacts.appending(path: "appcast.xml"), atomically: true, encoding: .utf8)
    try "Fixture release notes".write(
      to: artifacts.appending(path: "Imaxe-1.2.3.md"),
      atomically: true,
      encoding: .utf8,
    )
    let manifest = [
      "version": "1.2.3",
      "build": "12",
      "commit": commit,
      "minimumSystemVersion": "15.6",
      "feedURL": feed,
      "publicEDKey": publicKey,
    ]
    try JSONEncoder().encode(manifest).write(to: artifacts.appending(path: "release.json"))
    try checksums()
    try Self.succeed(
      "/usr/bin/xcrun",
      ["swiftc", root.appending(path: "Scripts/validate-release.swift").path, "-o", verifier.path],
    )
  }

  func checksums() throws {
    let names = ["Imaxe-1.2.3.zip", "Imaxe-1.2.3.md", "appcast.xml", "release.json"]
    let lines = try names.map { name in
      let digest = try SHA256.hash(data: Data(contentsOf: artifacts.appending(path: name)))
        .map { String(format: "%02x", $0) }.joined()
      return "\(digest)  \(name)"
    }
    try (lines.joined(separator: "\n") + "\n")
      .write(to: artifacts.appending(path: "SHA256SUMS.txt"), atomically: true, encoding: .utf8)
  }

  func verify(commit: String? = nil) async throws -> (status: Int32, output: String) {
    let expectedCommit = commit ?? self.commit
    return try await Task.detached {
      try Self.run(verifier.path, [artifacts.path, expectedCommit])
    }.value
  }

  static func succeed(_ executable: String, _ arguments: [String]) throws {
    let result = try run(executable, arguments)
    if result.status != 0 {
      throw NSError(
        domain: "ReleaseFixture",
        code: Int(result.status),
        userInfo: [NSLocalizedDescriptionKey: result.output],
      )
    }
  }

  static func run(
    _ executable: String,
    _ arguments: [String],
  ) throws -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (
      process.terminationStatus,
      String(data: data, encoding: .utf8) ?? "Non-UTF8 process output",
    )
  }
}
