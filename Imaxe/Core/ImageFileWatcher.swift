//
//  ImageFileWatcher.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/28.
//

import Darwin
import Dispatch
import Foundation

final nonisolated class ImageFileWatcher: @unchecked Sendable {
  private let url: URL
  private let queue = DispatchQueue(label: "com.imaxe.Imaxe.imageFileWatcher")
  private let onChange: @MainActor @Sendable () -> Void
  private var source: (any DispatchSourceFileSystemObject)?
  private var settleGeneration = 0
  private var lastSnapshot: FileSnapshot?

  init(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
    self.url = url
    self.onChange = onChange
    lastSnapshot = FileSnapshot(url: url)
    start()
  }

  deinit {
    settleGeneration += 1
    source?.cancel()
  }

  private func start() {
    stopSource()

    let fileDescriptor = open(url.filePath, O_EVTONLY)
    guard fileDescriptor >= 0 else { return }

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
    self.source = source
  }

  private func stopSource() {
    source?.cancel()
    source = nil
  }

  private func fileDidChange(_ event: DispatchSource.FileSystemEvent) {
    if event.contains(.delete) || event.contains(.rename) || event.contains(.revoke) {
      start()
    }

    settleGeneration += 1
    let deadline = DispatchTime.now() + Constants.stableFileCheckDeadline
    scheduleStableFileCheck(
      previousSnapshot: nil,
      deadline: deadline,
      generation: settleGeneration,
    )
  }

  private func scheduleStableFileCheck(
    previousSnapshot: FileSnapshot?,
    deadline: DispatchTime,
    generation: Int,
  ) {
    queue.asyncAfter(deadline: .now() + Constants.pollingIntervalOnFileChange) { [weak self] in
      guard let self else { return }
      guard generation == settleGeneration else { return }

      let currentSnapshot = FileSnapshot(url: url)

      if let currentSnapshot,
         currentSnapshot == previousSnapshot,
         currentSnapshot != lastSnapshot
      {
        lastSnapshot = currentSnapshot
        Task { @MainActor [onChange] in
          onChange()
        }
        return
      }

      guard DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds else { return }
      scheduleStableFileCheck(
        previousSnapshot: currentSnapshot,
        deadline: deadline,
        generation: generation,
      )
    }
  }
}
