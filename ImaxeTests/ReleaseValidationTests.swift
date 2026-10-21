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
    let checksum = try await fixture.verify()
    #expect(checksum.status != 0 && checksum.output.contains("Checksum mismatch"))
    try fixture.checksums()
    let signature = try await fixture.verify()
    #expect(signature.status != 0 && signature.output.contains("Invalid update signature"))
    try originalZIP.write(to: zip)
    try fixture.checksums()

    let notes = fixture.artifacts.appending(path: "Imaxe-1.2.3.md")
    let originalNotes = try String(contentsOf: notes, encoding: .utf8)
    try "Changed after signing".write(to: notes, atomically: true, encoding: .utf8)
    let changedNotes = try await fixture.verify()
    #expect(changedNotes.status != 0 && changedNotes.output.contains("Release notes differ"))
    try originalNotes.write(to: notes, atomically: true, encoding: .utf8)

    let appcast = fixture.artifacts.appending(path: "appcast.xml")
    let originalXML = try String(contentsOf: appcast, encoding: .utf8)
    try fixture.updateAppcast(
      originalXML.replacingOccurrences(of: "/download/v1.2.3/", with: "/download/latest/"),
    )
    let url = try await fixture.verify()
    #expect(url.status != 0 && url.output.contains("download URL"))
    try fixture.updateAppcast(originalXML)

    let commit = try await fixture.verify(commit: String(repeating: "b", count: 40))
    #expect(commit.status != 0 && commit.output.contains("commit"))

    let sourceInfo = fixture.root.appending(path: "Imaxe/Info.plist")
    let originalInfo = try Data(contentsOf: sourceInfo)
    var info = try #require(PropertyListSerialization.propertyList(
      from: originalInfo,
      format: nil,
    ) as? [String: Any])
    info["SUPublicEDKey"] = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
      .base64EncodedString()
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: sourceInfo)
    let key = try await fixture.verify()
    #expect(key.status != 0 && key.output.contains("Invalid update signature"))
    try originalInfo.write(to: sourceInfo)

    try fixture.updateAppcast(
      originalXML.replacingOccurrences(of: "<sparkle:version>12", with: "<sparkle:version>13"),
    )
    let version = try await fixture.verify()
    #expect(version.status != 0 && version.output.contains("CFBundleVersion mismatch"))

    try fixture.updateAppcast(
      originalXML.replacingOccurrences(of: "# Imaxe 1.2.3", with: "# Imaxe 1.2.3 (12)"),
    )
    let title = try await fixture.verify()
    #expect(title.status != 0 && title.output.contains("without a build number"))
  }

  @Test func `ad hoc hardened release rejects missing library validation exception`() async throws {
    let fixture = try await Task.detached {
      try ReleaseFixture(disableLibraryValidation: false)
    }.value
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let result = try await fixture.verify()
    #expect(result.status != 0 && result.output.contains("library validation exception"))
  }

  @Test func `release verifies using history XML without JSON or Markdown attachments`(
  ) async throws {
    let fixture = try await Task.detached { try ReleaseFixture() }.value
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try FileManager.default.removeItem(at: fixture.artifacts.appending(path: "Imaxe-1.2.3.md"))
    #expect(!FileManager.default
      .fileExists(atPath: fixture.artifacts.appending(path: "release.json").path))
    let result = try await fixture.verify()
    #expect(result.status == 0, "\(result.output)")
  }
}

private nonisolated struct ReleaseFixture: Sendable {
  let root: URL
  let artifacts: URL
  let verifier: URL
  let commit = String(repeating: "a", count: 40)

  init(disableLibraryValidation: Bool = true) throws {
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
    try signApplication(disableLibraryValidation: disableLibraryValidation)
    let zip = artifacts.appending(path: "Imaxe-1.2.3.zip")
    try Self.succeed(
      "/usr/bin/ditto",
      ["-c", "-k", "--keepParent", root.appending(path: "Imaxe.app").path, zip.path],
    )
    let data = try Data(contentsOf: zip)
    let signature = try key.signature(for: data).base64EncodedString()
    let downloadURL = "https://github.com/eureka-0/Imaxe/releases/download/v1.2.3/Imaxe-1.2.3.zip"
    let notes = "# Imaxe 1.2.3\n\nFixture release notes"
    let notesURL = "https://github.com/eureka-0/Imaxe/releases/tag/v1.2.3"
    let xml = """
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
      xmlns:imaxe="https://github.com/eureka-0/Imaxe/appcast">
      <channel><item>
        <imaxe:sourceCommit>\(commit)</imaxe:sourceCommit>
        <sparkle:version>12</sparkle:version>
        <sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>15.6</sparkle:minimumSystemVersion>
        <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
        <sparkle:fullReleaseNotesLink>\(notesURL)</sparkle:fullReleaseNotesLink>
        <description sparkle:format="markdown"><![CDATA[\(notes)]]></description>
        <enclosure url="\(downloadURL)"
          length="\(data.count)" type="application/octet-stream" sparkle:edSignature="\(signature)"/>
      </item></channel>
    </rss>
    """
    try xml.write(to: artifacts.appending(path: "appcast.xml"), atomically: true, encoding: .utf8)
    try notes.write(
      to: artifacts.appending(path: "Imaxe-1.2.3.md"),
      atomically: true,
      encoding: .utf8,
    )
    try checksums()
    try Self.succeed(
      "/usr/bin/xcrun",
      ["swiftc", root.appending(path: "Scripts/validate-release.swift").path, "-o", verifier.path],
    )
  }

  private func signApplication(disableLibraryValidation: Bool) throws {
    var arguments = ["--sign", "-", "--options", "runtime"]
    if disableLibraryValidation {
      let entitlements = ["com.apple.security.cs.disable-library-validation": true]
      let data = try PropertyListSerialization.data(
        fromPropertyList: entitlements,
        format: .xml,
        options: 0,
      )
      let entitlementURL = root.appending(path: "Launch.entitlements")
      try data.write(to: entitlementURL)
      arguments += ["--entitlements", entitlementURL.path]
    }
    arguments.append(root.appending(path: "Imaxe.app").path)
    try Self.succeed("/usr/bin/codesign", arguments)
  }

  func checksums() throws {
    let names = ["Imaxe-1.2.3.zip"]
    let lines = try names.map { name in
      let digest = try SHA256.hash(data: Data(contentsOf: artifacts.appending(path: name)))
        .map { String(format: "%02x", $0) }.joined()
      return "\(digest)  \(name)"
    }
    try (lines.joined(separator: "\n") + "\n")
      .write(to: artifacts.appending(path: "SHA256SUMS.txt"), atomically: true, encoding: .utf8)
  }

  func updateAppcast(_ xml: String) throws {
    try xml.write(to: artifacts.appending(path: "appcast.xml"), atomically: true, encoding: .utf8)
    try checksums()
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
