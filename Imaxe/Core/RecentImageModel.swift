//
//  RecentImage.swift
//  Imaxe
//
//  Created by lxlong on 2026/7/3.
//

import Foundation
import Observation
import SwiftData

@Model
final class RecentImage {
  @Attribute(.unique) var location: String
  var isFileURL: Bool
  var displayName: String
  var lastOpenedAt: Date

  init(url: URL, lastOpenedAt: Date = .now) {
    location = Self.location(for: url)
    isFileURL = url.isFileURL
    displayName = Self.displayName(for: url)
    self.lastOpenedAt = lastOpenedAt
  }

  var url: URL? {
    if isFileURL {
      return URL(fileURLWithPath: location)
    }

    return URL(string: location)
  }

  func update(from url: URL, lastOpenedAt: Date = .now) {
    location = Self.location(for: url)
    isFileURL = url.isFileURL
    displayName = Self.displayName(for: url)
    self.lastOpenedAt = lastOpenedAt
  }

  static func location(for url: URL) -> String {
    if url.isFileURL {
      return url.standardizedFileURL.path
    }

    return url.absoluteString
  }

  private static func displayName(for url: URL) -> String {
    let name = url.lastPathComponent
    return name.isEmpty ? location(for: url) : name
  }
}

struct RecentImageItem: Identifiable, Hashable {
  let id: String
  let location: String
  let isFileURL: Bool
  let displayName: String

  init(recentImage: RecentImage) {
    id = recentImage.location
    location = recentImage.location
    isFileURL = recentImage.isFileURL
    displayName = recentImage.displayName
  }

  var url: URL? {
    if isFileURL {
      return URL(fileURLWithPath: location)
    }

    return URL(string: location)
  }
}

@Observable
final class RecentImagesSnapshot {
  var items: [RecentImageItem]

  init(items: [RecentImageItem] = []) {
    self.items = items
  }
}

enum RecentImagesStore {
  static let defaultLimit = 100

  static func recordOpened(
    _ url: URL,
    in modelContext: ModelContext,
    openedAt: Date = .now,
    limit: Int = defaultLimit,
  ) throws {
    let location = RecentImage.location(for: url)
    var descriptor = FetchDescriptor<RecentImage>(
      predicate: #Predicate<RecentImage> { recentImage in
        recentImage.location == location
      },
    )
    descriptor.fetchLimit = 1

    if let recentImage = try modelContext.fetch(descriptor).first {
      recentImage.update(from: url, lastOpenedAt: openedAt)
    } else {
      modelContext.insert(RecentImage(url: url, lastOpenedAt: openedAt))
    }

    try trim(to: limit, in: modelContext)
    try modelContext.save()
  }

  static func clear(in modelContext: ModelContext) throws {
    try modelContext.delete(model: RecentImage.self)
    try modelContext.save()
  }

  private static func trim(to limit: Int, in modelContext: ModelContext) throws {
    guard limit > 0 else {
      try modelContext.delete(model: RecentImage.self)
      return
    }

    let descriptor = FetchDescriptor<RecentImage>(
      sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)],
    )
    let recentImages = try modelContext.fetch(descriptor)
    for recentImage in recentImages.dropFirst(limit) {
      modelContext.delete(recentImage)
    }
  }
}
