//
//  FileLocationPicker.swift
//  Imaxe
import AppKit
import SwiftUI

struct FileLocationPicker: NSViewRepresentable {
  let directoryURL: URL?
  let onSelectDirectory: (URL) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onSelectDirectory: onSelectDirectory)
  }

  func makeNSView(context: Context) -> NSPathControl {
    let pathControl = NSPathControl()
    pathControl.pathStyle = .popUp
    pathControl.isEditable = true
    pathControl.url = directoryURL
    pathControl.delegate = context.coordinator
    pathControl.target = context.coordinator
    pathControl.action = #selector(Coordinator.selectDirectory(_:))
    return pathControl
  }

  func updateNSView(_ pathControl: NSPathControl, context: Context) {
    context.coordinator.onSelectDirectory = onSelectDirectory
    if pathControl.url != directoryURL {
      pathControl.url = directoryURL
    }
  }

  final class Coordinator: NSObject, NSPathControlDelegate {
    var onSelectDirectory: (URL) -> Void

    init(onSelectDirectory: @escaping (URL) -> Void) {
      self.onSelectDirectory = onSelectDirectory
    }

    @objc func selectDirectory(_ pathControl: NSPathControl) {
      guard let url = pathControl.url else { return }
      onSelectDirectory(url)
    }

    func pathControl(_: NSPathControl, willDisplay openPanel: NSOpenPanel) {
      openPanel.canChooseFiles = false
      openPanel.canChooseDirectories = true
      openPanel.allowsMultipleSelection = false
      openPanel.canCreateDirectories = true
    }
  }
}
