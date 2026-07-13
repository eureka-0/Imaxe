//
//  RecentImagesTests.swift
//  ImaxeTests
//
//  Created by lxlong on 2026/6/14.
//

@testable import Imaxe
import SwiftData
import SwiftUI
import Testing

@MainActor
@Suite("Recent Images")
struct RecentImagesTests {
  private final class Harness {
    let container: ModelContainer
    let context: ModelContext
    let thumbnailDirectoryURL: URL
    let limit: Int

    init(limit: Int = AppSettings.Defaults.recentImagesCountLimit) throws {
      self.limit = limit
      thumbnailDirectoryURL = try TestSupport.temporaryDirectory(
        prefix: "imaxe-recent-thumbnail-cache",
      )
      container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      context = ModelContext(container)
    }

    deinit {
      try? FileManager.default.removeItem(at: thumbnailDirectoryURL)
    }

    func record(_ url: URL, openedAt: Date = .now) async throws {
      try await RecentImagesStore.recordOpened(
        url,
        in: context,
        openedAt: openedAt,
        limit: limit,
        thumbnailDirectoryURL: thumbnailDirectoryURL,
      )
    }

    func fetch(limit: Int? = nil) throws -> [RecentImage] {
      try RecentImagesStore.fetchRecentImages(
        in: context,
        limit: limit ?? self.limit,
        thumbnailDirectoryURL: thumbnailDirectoryURL,
      )
    }

    func remove(path: String) throws {
      try RecentImagesStore.remove(
        path: path,
        in: context,
        limit: limit,
        thumbnailDirectoryURL: thumbnailDirectoryURL,
      )
    }

    func clear() throws {
      try RecentImagesStore.clear(
        in: context,
        thumbnailDirectoryURL: thumbnailDirectoryURL,
      )
    }
  }

  @Test func `recent images are updated sorted and cleared`() async throws {
    let harness = try Harness()
    let firstURL = URL(fileURLWithPath: "/tmp/first.png")
    let secondURL = URL(fileURLWithPath: "/tmp/second.png")

    try await harness.record(firstURL, openedAt: Date(timeIntervalSince1970: 1))
    try await harness.record(secondURL, openedAt: Date(timeIntervalSince1970: 2))
    try await harness.record(firstURL, openedAt: Date(timeIntervalSince1970: 3))

    let recentImages = try harness.fetch()
    #expect(recentImages.map(\.fileName) == ["first.png", "second.png"])
    #expect(recentImages.first?.lastOpenedAt == Date(timeIntervalSince1970: 3))

    try harness.clear()
    #expect(try harness.fetch().isEmpty)
  }

  @Test func `recent images honor the app default count limit`() async throws {
    let harness = try Harness(limit: AppSettings.Defaults.recentImagesCountLimit)

    try await harness.record(
      URL(fileURLWithPath: "/tmp/first.png"),
      openedAt: Date(timeIntervalSince1970: 1),
    )
    try await harness.record(
      URL(fileURLWithPath: "/tmp/second.png"),
      openedAt: Date(timeIntervalSince1970: 2),
    )

    #expect(try harness.fetch().map(\.fileName) == ["second.png", "first.png"])
  }

  @Test func `recent images are trimmed to configured count limit`() async throws {
    let harness = try Harness(limit: 3)
    try await harness.record(
      URL(fileURLWithPath: "/tmp/first.png"),
      openedAt: Date(timeIntervalSince1970: 1),
    )
    try await harness.record(
      URL(fileURLWithPath: "/tmp/second.png"),
      openedAt: Date(timeIntervalSince1970: 2),
    )
    try await harness.record(
      URL(fileURLWithPath: "/tmp/third.png"),
      openedAt: Date(timeIntervalSince1970: 3),
    )

    #expect(try harness.fetch(limit: 2).map(\.fileName) == ["third.png", "second.png"])
  }

  @Test func `recent images store metadata and cleanup thumbnail cache`() async throws {
    let harness = try Harness()
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-recent-metadata")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "image.png")
    try TestSupport.pngData(width: 80, height: 40).write(to: url)

    try await harness.record(url)

    let recent = try #require(harness.fetch().first)
    let thumbnailKey = try #require(recent.thumbnailCacheKey)
    let thumbnailURL = ImageThumbnailCache.thumbnailURL(
      for: thumbnailKey,
      directoryURL: harness.thumbnailDirectoryURL,
    )
    let resourceValues = try url.resourceValues(forKeys: [
      .contentModificationDateKey,
      .fileSizeKey,
    ])
    #expect(recent.sourceFileSize == resourceValues.fileSize)
    #expect(recent.sourceContentModificationDate == resourceValues.contentModificationDate)
    #expect(thumbnailURL.fileExists)

    try harness.remove(path: url.filePath)
    #expect(!thumbnailURL.fileExists)
  }

  @Test func `missing recent images are pruned with thumbnail cache`() async throws {
    let harness = try Harness()
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-recent-prune")
    defer { try? FileManager.default.removeItem(at: directory) }
    let existingURL = directory.appending(path: "existing.png")
    let missingURL = directory.appending(path: "missing.png")
    try TestSupport.pngData(width: 80, height: 40).write(to: existingURL)
    try TestSupport.pngData(width: 80, height: 40).write(to: missingURL)
    try await harness.record(existingURL, openedAt: Date(timeIntervalSince1970: 1))
    try await harness.record(missingURL, openedAt: Date(timeIntervalSince1970: 2))

    let missingRecent = try #require(harness.fetch().first { $0.path == missingURL.filePath })
    let missingThumbnailKey = try #require(missingRecent.thumbnailCacheKey)
    let missingThumbnailURL = ImageThumbnailCache.thumbnailURL(
      for: missingThumbnailKey,
      directoryURL: harness.thumbnailDirectoryURL,
    )
    try FileManager.default.removeItem(at: missingURL)

    let removedCount = try RecentImagesStore.removeMissingFiles(
      in: harness.context,
      limit: harness.limit,
      thumbnailDirectoryURL: harness.thumbnailDirectoryURL,
    )

    #expect(removedCount == 1)
    #expect(try harness.fetch().map(\.path) == [existingURL.filePath])
    #expect(!missingThumbnailURL.fileExists)
  }

  @Test func `opening missing recent image removes item and thumbnail cache`() async throws {
    let harness = try Harness()
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-recent-open-missing")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "missing.png")
    try TestSupport.pngData(width: 80, height: 40).write(to: url)
    try await harness.record(url)

    let recent = try #require(harness.fetch().first)
    let thumbnailKey = try #require(recent.thumbnailCacheKey)
    let thumbnailURL = ImageThumbnailCache.thumbnailURL(
      for: thumbnailKey,
      directoryURL: harness.thumbnailDirectoryURL,
    )
    try FileManager.default.removeItem(at: url)

    let session = ImageSession()
    session.removeRecentImage = { path in
      try harness.remove(path: path)
    }
    session.openRecentImage(recent)

    try await TestSupport.waitUntil(timeout: .seconds(2)) {
      (try? harness.fetch().isEmpty) == true
    }

    #expect(!thumbnailURL.fileExists)
    #expect(session.alertTitle == "Recent Image Removed")
  }

  @Test func `lowered count limit removes trimmed thumbnail cache`() async throws {
    let harness = try Harness(limit: 3)
    let directory = try TestSupport.temporaryDirectory(prefix: "imaxe-recent-trim")
    defer { try? FileManager.default.removeItem(at: directory) }
    let urls = ["first", "second", "third"].map { directory.appending(path: "\($0).png") }
    for (index, url) in urls.enumerated() {
      try TestSupport.pngData(width: 80, height: 40).write(to: url)
      try await harness.record(url, openedAt: Date(timeIntervalSince1970: Double(index + 1)))
    }

    let firstRecent = try #require(harness.fetch().first { $0.path == urls[0].filePath })
    let firstThumbnailKey = try #require(firstRecent.thumbnailCacheKey)
    let firstThumbnailURL = ImageThumbnailCache.thumbnailURL(
      for: firstThumbnailKey,
      directoryURL: harness.thumbnailDirectoryURL,
    )
    #expect(firstThumbnailURL.fileExists)

    #expect(try harness.fetch(limit: 2).map(\.path) == [urls[2].filePath, urls[1].filePath])
    #expect(!firstThumbnailURL.fileExists)
  }
}
