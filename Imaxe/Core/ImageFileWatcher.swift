// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Xinlong Liu.

import Darwin
import Dispatch
import Foundation

final nonisolated class ImageFileWatcher: @unchecked Sendable {
  enum Event: Equatable, Sendable {
    case modified
    case replaced
    case deleted
    case recreated
  }

  private enum ObservedSnapshot: Equatable {
    case missing
    case present(FileSnapshot)
  }

  private let url: URL
  private let queue = DispatchQueue(label: "com.imaxe.Imaxe.imageFileWatcher")
  private let onEvent: @MainActor @Sendable (Event) -> Void
  private var fileSource: (any DispatchSourceFileSystemObject)?
  private var directorySource: (any DispatchSourceFileSystemObject)?
  private var settleGeneration = 0
  private var lastSnapshot: FileSnapshot?
  private var sawInvalidatingFileEvent = false
  private var fileRecoveryScheduled = false
  private var directoryRecoveryScheduled = false

  // File checking and polling intervals
  private let stableFileCheckDeadline: DispatchTimeInterval = .seconds(10)
  private let pollingIntervalOnFileChange: DispatchTimeInterval = .milliseconds(150)

  init(url: URL, onEvent: @escaping @MainActor @Sendable (Event) -> Void) {
    self.url = url
    self.onEvent = onEvent
    lastSnapshot = FileSnapshot(url: url)
    startDirectorySource()
    startFileSource()
  }

  deinit {
    settleGeneration += 1
    fileSource?.cancel()
    directorySource?.cancel()
  }

  private var directoryURL: URL {
    url.deletingLastPathComponent()
  }

  private func startFileSource() {
    stopFileSource()

    let fileDescriptor = open(url.filePath, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      scheduleFileRecovery()
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke],
      queue: queue,
    )
    source.setEventHandler { [weak self, weak source] in
      let event = source?.data ?? []
      self?.fileDidChange(event)
    }
    source.setCancelHandler { [fileDescriptor] in
      close(fileDescriptor)
    }
    source.activate()
    fileSource = source
  }

  private func startDirectorySource() {
    stopDirectorySource()

    let fileDescriptor = open(directoryURL.filePath, O_EVTONLY)
    guard fileDescriptor >= 0 else {
      scheduleDirectoryRecovery()
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .rename, .delete, .revoke],
      queue: queue,
    )
    source.setEventHandler { [weak self, weak source] in
      self?.directoryDidChange(source?.data ?? [])
    }
    source.setCancelHandler { [fileDescriptor] in
      close(fileDescriptor)
    }
    source.activate()
    directorySource = source
  }

  private func stopFileSource() {
    fileSource?.cancel()
    fileSource = nil
  }

  private func stopDirectorySource() {
    directorySource?.cancel()
    directorySource = nil
  }

  private func fileDidChange(_ event: DispatchSource.FileSystemEvent) {
    if event.contains(.delete) || event.contains(.rename) || event.contains(.revoke) {
      sawInvalidatingFileEvent = true
      stopFileSource()
      scheduleFileRecovery()
    }

    scheduleStableFileCheck()
  }

  private func directoryDidChange(_ event: DispatchSource.FileSystemEvent) {
    if event.contains(.delete) || event.contains(.rename) || event.contains(.revoke) {
      stopDirectorySource()
      scheduleDirectoryRecovery()
    }

    scheduleStableFileCheck()
  }

  private func scheduleStableFileCheck() {
    settleGeneration += 1
    let deadline = DispatchTime.now() + stableFileCheckDeadline
    scheduleStableFileCheck(
      previousSnapshot: nil,
      deadline: deadline,
      generation: settleGeneration,
    )
  }

  private func scheduleStableFileCheck(
    previousSnapshot: ObservedSnapshot?,
    deadline: DispatchTime,
    generation: Int,
  ) {
    queue.asyncAfter(deadline: .now() + pollingIntervalOnFileChange) { [weak self] in
      guard let self, generation == settleGeneration else { return }

      let currentSnapshot = observedSnapshot()

      if currentSnapshot == previousSnapshot {
        commit(currentSnapshot)
        return
      }

      guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else {
        commit(currentSnapshot)
        return
      }
      scheduleStableFileCheck(
        previousSnapshot: currentSnapshot,
        deadline: deadline,
        generation: generation,
      )
    }
  }

  private func observedSnapshot() -> ObservedSnapshot {
    FileSnapshot(url: url).map(ObservedSnapshot.present) ?? .missing
  }

  private func commit(_ observedSnapshot: ObservedSnapshot) {
    switch observedSnapshot {
    case .missing:
      stopFileSource()
      scheduleFileRecovery()
      guard lastSnapshot != nil else { return }

      lastSnapshot = nil
      sawInvalidatingFileEvent = false
      deliver(.deleted)

    case let .present(currentSnapshot):
      if fileSource == nil {
        startFileSource()
      }

      let event: Event?
      if let lastSnapshot {
        guard currentSnapshot != lastSnapshot else {
          sawInvalidatingFileEvent = false
          return
        }
        event = sawInvalidatingFileEvent || !currentSnapshot.hasSameFileIdentity(as: lastSnapshot)
          ? .replaced
          : .modified
      } else {
        event = .recreated
      }

      lastSnapshot = currentSnapshot
      sawInvalidatingFileEvent = false
      if let event {
        deliver(event)
      }
    }
  }

  private func deliver(_ event: Event) {
    Task { @MainActor [onEvent] in
      onEvent(event)
    }
  }

  private func scheduleFileRecovery() {
    guard !fileRecoveryScheduled else { return }
    fileRecoveryScheduled = true

    queue.asyncAfter(deadline: .now() + pollingIntervalOnFileChange) { [weak self] in
      guard let self else { return }
      fileRecoveryScheduled = false
      guard fileSource == nil else { return }

      if FileSnapshot(url: url) != nil {
        scheduleStableFileCheck()
      } else {
        scheduleFileRecovery()
      }
    }
  }

  private func scheduleDirectoryRecovery() {
    guard !directoryRecoveryScheduled else { return }
    directoryRecoveryScheduled = true

    queue.asyncAfter(deadline: .now() + pollingIntervalOnFileChange) { [weak self] in
      guard let self else { return }
      directoryRecoveryScheduled = false
      guard directorySource == nil else { return }

      startDirectorySource()
    }
  }
}
