// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Combine
import Sparkle
import SwiftUI

@Observable
final class UpdateSettings {
  private let updater: SPUUpdater
  private var subscriptions: Set<AnyCancellable> = []

  private(set) var automaticallyChecksForUpdates: Bool
  private(set) var automaticallyDownloadsUpdates: Bool
  private(set) var allowsAutomaticUpdates: Bool

  init(updater: SPUUpdater) {
    self.updater = updater
    automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    allowsAutomaticUpdates = updater.allowsAutomaticUpdates

    updater.publisher(for: \.automaticallyChecksForUpdates)
      .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
      .store(in: &subscriptions)
    updater.publisher(for: \.automaticallyDownloadsUpdates)
      .sink { [weak self] in self?.automaticallyDownloadsUpdates = $0 }
      .store(in: &subscriptions)
    updater.publisher(for: \.allowsAutomaticUpdates)
      .sink { [weak self] in self?.allowsAutomaticUpdates = $0 }
      .store(in: &subscriptions)
  }

  func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
    updater.automaticallyChecksForUpdates = enabled
    automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    allowsAutomaticUpdates = updater.allowsAutomaticUpdates
  }

  func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
    updater.automaticallyDownloadsUpdates = enabled
    automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
  }
}
