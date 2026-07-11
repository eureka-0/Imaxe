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
  @Test func `recent images are updated sorted and cleared`() async throws {
    try await TestSupport.withRecentImagesCountLimit(AppSettings.Defaults.recentImagesCountLimit) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let firstURL = URL(fileURLWithPath: "/tmp/first.png")
      let secondURL = URL(fileURLWithPath: "/tmp/second.png")

      try await RecentImagesStore.recordOpened(
        firstURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try await RecentImagesStore.recordOpened(
        secondURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )
      try await RecentImagesStore.recordOpened(
        firstURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 3),
      )

      let descriptor = FetchDescriptor<RecentImage>(
        sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)],
      )
      let recentImages = try context.fetch(descriptor)

      #expect(recentImages.compactMap(\.url).map(\.lastPathComponent) == [
        "first.png",
        "second.png",
      ])
      #expect(recentImages.first?.lastOpenedAt == Date(timeIntervalSince1970: 3))

      try RecentImagesStore.clear(in: context)

      #expect(try context.fetch(descriptor).isEmpty)
    }
  }

  @Test func `recent images use default count limit when preference is unset`() async throws {
    try await TestSupport.withRecentImagesCountLimit(nil) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)

      try await RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/first.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try await RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/second.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )

      let recentImages = try RecentImagesStore.fetchRecentImages(in: context)

      #expect(recentImages.map(\.fileName) == ["second.png", "first.png"])
    }
  }

  @Test func `recent images are trimmed to configured count limit`() async throws {
    try await TestSupport.withRecentImagesCountLimit(3) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)

      try await RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/first.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try await RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/second.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )
      try await RecentImagesStore.recordOpened(
        URL(fileURLWithPath: "/tmp/third.png"),
        in: context,
        openedAt: Date(timeIntervalSince1970: 3),
      )

      UserDefaults.standard.set(2, forKey: AppSettings.Keys.recentImagesCountLimit.rawValue)

      let recentImages = try RecentImagesStore.fetchRecentImages(in: context)

      #expect(recentImages.map(\.fileName) == ["third.png", "second.png"])
    }
  }

  @Test func `recent images store file metadata and cleanup thumbnail cache`() async throws {
    try await TestSupport.withRecentImagesCountLimit(AppSettings.Defaults.recentImagesCountLimit) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let url = URL.temporaryDirectory
        .appending(path: "imaxe-thumbnail-cache-\(UUID().uuidString).png")
      try TestSupport.pngData(width: 80, height: 40).write(to: url)

      try await RecentImagesStore.recordOpened(url, in: context)

      let recentDescriptor = FetchDescriptor<RecentImage>()
      let recent = try #require(context.fetch(recentDescriptor).first)
      let thumbnailKey = try #require(recent.thumbnailCacheKey)
      let thumbnailURL = ImageThumbnailCache.thumbnailURL(for: thumbnailKey)

      let resourceValues = try recent.url.resourceValues(forKeys: [
        .contentModificationDateKey,
        .fileSizeKey,
      ])
      #expect((resourceValues.fileSize ?? 0) > 0)
      #expect(resourceValues.contentModificationDate != nil)
      #expect(recent.sourceFileSize == resourceValues.fileSize)
      #expect(recent.sourceContentModificationDate == resourceValues.contentModificationDate)
      #expect(FileManager.default.fileExists(atPath: thumbnailURL.filePath))

      try RecentImagesStore.remove(path: url.filePath, in: context)
      #expect(!FileManager.default.fileExists(atPath: thumbnailURL.filePath))
    }
  }

  @Test func `missing recent images are pruned with thumbnail cache`() async throws {
    try await TestSupport.withRecentImagesCountLimit(AppSettings.Defaults.recentImagesCountLimit) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let existingURL = URL.temporaryDirectory
        .appending(path: "imaxe-existing-recent-\(UUID().uuidString).png")
      let missingURL = URL.temporaryDirectory
        .appending(path: "imaxe-pruned-recent-\(UUID().uuidString).png")
      defer {
        try? FileManager.default.removeItem(at: existingURL)
        try? FileManager.default.removeItem(at: missingURL)
      }

      try TestSupport.pngData(width: 80, height: 40).write(to: existingURL)
      try TestSupport.pngData(width: 80, height: 40).write(to: missingURL)
      try await RecentImagesStore.recordOpened(
        existingURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try await RecentImagesStore.recordOpened(
        missingURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )

      var missingDescriptor = FetchDescriptor<RecentImage>(
        predicate: #Predicate<RecentImage> { recentImage in
          recentImage.path == missingURL.filePath
        },
      )
      missingDescriptor.fetchLimit = 1
      let missingRecent = try #require(context.fetch(missingDescriptor).first)
      let missingThumbnailKey = try #require(missingRecent.thumbnailCacheKey)
      let missingThumbnailURL = ImageThumbnailCache.thumbnailURL(for: missingThumbnailKey)
      try FileManager.default.removeItem(at: missingURL)

      let removedCount = try RecentImagesStore.removeMissingFiles(in: context)

      let recentImages = try RecentImagesStore.fetchRecentImages(in: context)
      #expect(removedCount == 1)
      #expect(recentImages.map(\.path) == [existingURL.filePath])
      #expect(!FileManager.default.fileExists(atPath: missingThumbnailURL.filePath))

      try RecentImagesStore.clear(in: context)
    }
  }

  @Test func `opening missing recent image removes recent item and thumbnail cache`() async throws {
    try await TestSupport.withRecentImagesCountLimit(AppSettings.Defaults.recentImagesCountLimit) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let url = URL.temporaryDirectory
        .appending(path: "imaxe-missing-recent-\(UUID().uuidString).png")
      try TestSupport.pngData(width: 80, height: 40).write(to: url)
      try await RecentImagesStore.recordOpened(url, in: context)

      let descriptor = FetchDescriptor<RecentImage>()
      let recent = try #require(context.fetch(descriptor).first)
      let thumbnailKey = try #require(recent.thumbnailCacheKey)
      let thumbnailURL = ImageThumbnailCache.thumbnailURL(for: thumbnailKey)
      try FileManager.default.removeItem(at: url)

      let session = ImageSession()
      session.removeRecentImage = { path in
        try RecentImagesStore.remove(path: path, in: context)
      }
      session.openRecentImage(recent)

      try await TestSupport.waitUntil(timeout: .seconds(2)) {
        (try? context.fetch(descriptor).isEmpty) == true
      }

      #expect(try context.fetch(descriptor).isEmpty)
      #expect(!FileManager.default.fileExists(atPath: thumbnailURL.filePath))
      #expect(session.alert?.title == "Recent Image Removed")
    }
  }

  @Test func `lowered recent images count limit removes trimmed thumbnail cache`() async throws {
    try await TestSupport.withRecentImagesCountLimit(3) {
      let container = try ModelContainer(
        for: RecentImage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true),
      )
      let context = ModelContext(container)
      let firstURL = URL.temporaryDirectory
        .appending(path: "imaxe-trimmed-first-\(UUID().uuidString).png")
      let secondURL = URL.temporaryDirectory
        .appending(path: "imaxe-trimmed-second-\(UUID().uuidString).png")
      let thirdURL = URL.temporaryDirectory
        .appending(path: "imaxe-trimmed-third-\(UUID().uuidString).png")
      defer {
        try? FileManager.default.removeItem(at: firstURL)
        try? FileManager.default.removeItem(at: secondURL)
        try? FileManager.default.removeItem(at: thirdURL)
        try? RecentImagesStore.clear(in: context)
      }

      try TestSupport.pngData(width: 80, height: 40).write(to: firstURL)
      try TestSupport.pngData(width: 80, height: 40).write(to: secondURL)
      try TestSupport.pngData(width: 80, height: 40).write(to: thirdURL)
      try await RecentImagesStore.recordOpened(
        firstURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 1),
      )
      try await RecentImagesStore.recordOpened(
        secondURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 2),
      )
      try await RecentImagesStore.recordOpened(
        thirdURL,
        in: context,
        openedAt: Date(timeIntervalSince1970: 3),
      )

      var firstDescriptor = FetchDescriptor<RecentImage>(
        predicate: #Predicate<RecentImage> { recentImage in
          recentImage.path == firstURL.filePath
        },
      )
      firstDescriptor.fetchLimit = 1
      let firstRecent = try #require(context.fetch(firstDescriptor).first)
      let firstThumbnailKey = try #require(firstRecent.thumbnailCacheKey)
      let firstThumbnailURL = ImageThumbnailCache.thumbnailURL(for: firstThumbnailKey)
      #expect(FileManager.default.fileExists(atPath: firstThumbnailURL.filePath))

      UserDefaults.standard.set(2, forKey: AppSettings.Keys.recentImagesCountLimit.rawValue)

      let recentImages = try RecentImagesStore.fetchRecentImages(in: context)

      #expect(recentImages.map(\.path) == [thirdURL.filePath, secondURL.filePath])
      #expect(!FileManager.default.fileExists(atPath: firstThumbnailURL.filePath))
    }
  }
}
