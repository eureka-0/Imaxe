// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Foundation
@testable import Imaxe
import Sparkle
import Testing

@Suite("Update Settings")
struct UpdateSettingsTests {
  @Test func `settings track external Sparkle changes and write user choices`() throws {
    let fixture = try UpdaterFixture()
    defer { fixture.remove() }
    let settings = UpdateSettings(updater: fixture.updater)
    #expect(!settings.automaticallyChecksForUpdates)
    fixture.updater.automaticallyChecksForUpdates = true
    #expect(settings.automaticallyChecksForUpdates)
    #expect(settings.allowsAutomaticUpdates)
    fixture.updater.automaticallyDownloadsUpdates = true
    #expect(settings.automaticallyDownloadsUpdates)

    settings.setAutomaticallyChecksForUpdates(false)
    #expect(!fixture.updater.automaticallyChecksForUpdates)
    #expect(!settings.allowsAutomaticUpdates)
    // Disabling checks does not silently overwrite the separate download preference.
    settings.setAutomaticallyChecksForUpdates(true)
    #expect(settings.automaticallyDownloadsUpdates)
    settings.setAutomaticallyDownloadsUpdates(false)
    #expect(!fixture.updater.automaticallyDownloadsUpdates)
    fixture.updater.automaticallyChecksForUpdates = false
    #expect(!settings.automaticallyChecksForUpdates)
  }

  @Test func `settings follow Sparkle restrictions on automatic downloading`() throws {
    let fixture = try UpdaterFixture(allowsDownloads: false)
    defer { fixture.remove() }
    let settings = UpdateSettings(updater: fixture.updater)
    settings.setAutomaticallyChecksForUpdates(true)
    #expect(settings.automaticallyChecksForUpdates)
    #expect(!settings.allowsAutomaticUpdates)
    settings.setAutomaticallyDownloadsUpdates(true)
    #expect(!settings.automaticallyDownloadsUpdates)
  }
}

private struct UpdaterFixture {
  let directory: URL
  let identifier: String
  let updater: SPUUpdater

  init(allowsDownloads: Bool = true) throws {
    directory = try TestSupport.temporaryDirectory(prefix: "imaxe-updater")
    identifier = "com.imaxe.tests.updates.\(UUID().uuidString)"
    let bundleURL = directory.appending(path: "Fixture.app")
    let contents = bundleURL.appending(path: "Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    var info: [String: Any] = [
      "CFBundleIdentifier": identifier,
      "CFBundleName": "Update fixture",
      "CFBundlePackageType": "APPL",
      "CFBundleVersion": "1",
      "SUEnableAutomaticChecks": false,
    ]
    if !allowsDownloads {
      info["SUAllowsAutomaticUpdates"] = false
    }
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: contents.appending(path: "Info.plist"))
    let bundle = try #require(Bundle(url: bundleURL))
    updater = SPUUpdater(
      hostBundle: bundle,
      applicationBundle: bundle,
      userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil),
      delegate: nil,
    )
  }

  func remove() {
    UserDefaults.standard.removePersistentDomain(forName: identifier)
    try? FileManager.default.removeItem(at: directory)
  }
}
