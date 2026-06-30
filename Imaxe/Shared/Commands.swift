//
//  Commands.swift
//  Imaxe
//
//  Created by lxlong on 2026/6/17.
//

import AppKit
import SwiftUI

struct FileOperationCommands: Commands {
  @FocusedValue(ImageSession.self) private var imageSession

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Divider()

      Button("Open Image...") {
        imageSession?.isImporterPresented = true
      }
      .keyboardShortcut("o", modifiers: .command)
      .disabled(imageSession == nil)

      Button("Open from Pasteboard") {
        imageSession?.openImageFromPasteboard()
      }
      .keyboardShortcut("v", modifiers: .command)
      .disabled(imageSession == nil)

      Menu("Open Recent") {
        Button("No Recent Items") {}
          .disabled(true)
      }
      .disabled(false)

      Divider()

      Button("Reveal in Finder") {
        imageSession?.revealCurrentImageInFinder()
      }
      .keyboardShortcut("r", modifiers: [.command, .shift])
      .disabled(imageSession?.currentImageInfo == nil && imageSession?.currentImage == nil)
    }
  }
}

struct ViewCommands: Commands {
  @FocusedValue(ImageSession.self) private var imageSession

  var body: some Commands {
    CommandGroup(after: .sidebar) {
      Button("Previous Image") {
        imageSession?.navigateToPreviousImage()
      }
      .keyboardShortcut(.leftArrow, modifiers: [])
      .disabled(imageSession?.folderNavigator?.canNavigateToPrevious != true)

      Button("Next Image") {
        imageSession?.navigateToNextImage()
      }
      .keyboardShortcut(.rightArrow, modifiers: [])
      .disabled(imageSession?.folderNavigator?.canNavigateToNext != true)

      Divider()

      Button("Zoom In") {
        imageSession?.zoomIn()
      }
      .keyboardShortcut("+", modifiers: .command)
      .disabled(imageSession?.currentImage == nil)

      Button("Zoom Out") {
        imageSession?.zoomOut()
      }
      .keyboardShortcut("-", modifiers: .command)
      .disabled(imageSession?.currentImage == nil)

      Button("Fit to Window") {
        imageSession?.fitToWindow()
      }
      .keyboardShortcut("0", modifiers: .command)
      .disabled(imageSession?.currentImage == nil)

      Button("Actual Size") {
        imageSession?.setZoomScale(1.0)
      }
      .keyboardShortcut("1", modifiers: .command)
      .disabled(imageSession?.currentImage == nil)

      Divider()
    }
  }
}

struct OpenRecentMenuSessionBridge: NSViewRepresentable {
  let imageSession: ImageSession

  func makeNSView(context _: Context) -> NSView {
    let view = OpenRecentSessionRegistrationView()
    view.imageSession = imageSession
    view.updateRegistration()
    return view
  }

  func updateNSView(_ nsView: NSView, context _: Context) {
    guard let view = nsView as? OpenRecentSessionRegistrationView else { return }

    view.imageSession = imageSession
    view.updateRegistration()
  }

  static func dismantleNSView(_ nsView: NSView, coordinator _: ()) {
    (nsView as? OpenRecentSessionRegistrationView)?.unregister()
  }

  private final class OpenRecentSessionRegistrationView: NSView {
    var imageSession: ImageSession?
    private weak var registeredWindow: NSWindow?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      updateRegistration()
    }

    func updateRegistration() {
      OpenRecentMenuController.shared.installIfNeeded()

      if registeredWindow !== window {
        unregister()
      }

      guard let window, let imageSession else { return }

      OpenRecentMenuController.shared.register(imageSession, for: window)
      registeredWindow = window
    }

    func unregister() {
      if let registeredWindow {
        OpenRecentMenuController.shared.unregister(window: registeredWindow)
      }
      registeredWindow = nil
    }
  }
}

final class OpenRecentMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
  static let shared = OpenRecentMenuController()

  private final class ImageSessionRegistration {
    weak var window: NSWindow?
    weak var imageSession: ImageSession?

    init(window: NSWindow, imageSession: ImageSession) {
      self.window = window
      self.imageSession = imageSession
    }
  }

  private static let menuItemIdentifier = NSUserInterfaceItemIdentifier("com.imaxe.openRecentMenu")

  private var registrations: [ObjectIdentifier: ImageSessionRegistration] = [:]
  private weak var recentMenuItem: NSMenuItem?
  private weak var recentMenu: NSMenu?
  private var installRetryCount = 0
  private var isObservingMenuUpdates = false
  private var isInstalling = false

  override private init() {
    super.init()
  }

  func startObservingMenuUpdates() {
    guard !isObservingMenuUpdates else {
      installIfNeeded()
      return
    }

    isObservingMenuUpdates = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationDidUpdate(_:)),
      name: NSApplication.didUpdateNotification,
      object: NSApp,
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(menuDidBeginTracking(_:)),
      name: NSMenu.didBeginTrackingNotification,
      object: nil,
    )

    installWhenMenuIsReady()
  }

  @objc private func applicationDidUpdate(_: Notification) {
    installIfNeeded()
  }

  @objc private func menuDidBeginTracking(_ notification: Notification) {
    guard let menu = notification.object as? NSMenu, isFileMenu(menu) else { return }

    installIfNeeded(repositionIfNeeded: false)
  }

  func installIfNeeded(repositionIfNeeded: Bool = true) {
    guard !isInstalling else { return }

    isInstalling = true
    defer { isInstalling = false }
    pruneRegistrations()

    guard let (fileMenu, insertionIndex) = fileMenuInsertionPoint() else {
      installWhenMenuIsReady()
      return
    }

    guard let item = existingOpenRecentItem(in: fileMenu) else {
      installWhenMenuIsReady()
      return
    }

    let submenu = item.submenu ?? NSMenu(title: "Open Recent")
    fileMenu.setSubmenu(submenu, for: item)
    configure(item, submenu: submenu)
    if repositionIfNeeded {
      move(item, to: insertionIndex, in: fileMenu)
    }
  }

  func register(_ imageSession: ImageSession, for window: NSWindow) {
    pruneRegistrations()
    registrations[ObjectIdentifier(window)] = ImageSessionRegistration(
      window: window,
      imageSession: imageSession,
    )
  }

  func unregister(window: NSWindow) {
    registrations[ObjectIdentifier(window)] = nil
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    rebuild(menu)
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(openRecentImage(_:)):
      currentImageSession() != nil && menuItem.representedObject is URL
    case #selector(clearRecentDocuments(_:)):
      !NSDocumentController.shared.recentDocumentURLs.isEmpty
    default:
      true
    }
  }

  @objc private func openRecentImage(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL,
          let imageSession = currentImageSession()
    else {
      NSSound.beep()
      return
    }

    imageSession.loadImage(from: url)
  }

  @objc private func clearRecentDocuments(_ sender: NSMenuItem) {
    NSDocumentController.shared.clearRecentDocuments(sender)

    if let recentMenu {
      rebuild(recentMenu)
      recentMenu.update()
    }
  }

  private func configure(_ item: NSMenuItem, submenu: NSMenu) {
    item.identifier = Self.menuItemIdentifier
    item.title = "Open Recent"
    item.isEnabled = true
    submenu.title = "Open Recent"
    submenu.delegate = self
    submenu.autoenablesItems = true
    recentMenuItem = item
    recentMenu = submenu
    installRetryCount = 0
    rebuild(submenu)
  }

  private func rebuild(_ menu: NSMenu) {
    menu.removeAllItems()

    let recentURLs = NSDocumentController.shared.recentDocumentURLs
    for url in recentURLs {
      let item = NSMenuItem(
        title: url.lastPathComponent,
        action: #selector(openRecentImage(_:)),
        keyEquivalent: "",
      )
      item.target = self
      item.representedObject = url
      item.image = fileIcon(for: url)
      item.toolTip = url.path
      menu.addItem(item)
    }

    if !recentURLs.isEmpty {
      menu.addItem(.separator())
    }

    let clearItem = NSMenuItem(
      title: "Clear Menu",
      action: #selector(clearRecentDocuments(_:)),
      keyEquivalent: "",
    )
    clearItem.target = self
    clearItem.isEnabled = !recentURLs.isEmpty
    menu.addItem(clearItem)
  }

  private func fileIcon(for url: URL) -> NSImage {
    let image = NSWorkspace.shared.icon(forFile: url.path)
    image.size = NSSize(width: 16, height: 16)
    return image
  }

  private func currentImageSession() -> ImageSession? {
    pruneRegistrations()

    if let imageSession = imageSession(for: NSApp.keyWindow) {
      return imageSession
    }

    if let imageSession = imageSession(for: NSApp.mainWindow) {
      return imageSession
    }

    return nil
  }

  private func imageSession(for window: NSWindow?) -> ImageSession? {
    guard let window else { return nil }
    return registrations[ObjectIdentifier(window)]?.imageSession
  }

  private func pruneRegistrations() {
    registrations = registrations.filter { _, registration in
      registration.window != nil && registration.imageSession != nil
    }
  }

  private func fileMenuInsertionPoint() -> (menu: NSMenu, index: Int)? {
    guard let mainMenu = NSApp.mainMenu else { return nil }

    for item in mainMenu.items {
      guard let submenu = item.submenu else { continue }

      if let pasteboardIndex = submenu.items.firstIndex(where: {
        $0.title == "Open from Pasteboard"
      }) {
        return (submenu, pasteboardIndex + 1)
      }
    }

    guard let fileMenu = mainMenu.item(withTitle: "File")?.submenu else {
      return nil
    }

    let fallbackIndex = fileMenu.items.firstIndex(where: { $0.title == "Open Image..." })
      .map { $0 + 1 } ?? fileMenu.items.count
    return (fileMenu, fallbackIndex)
  }

  private func existingOpenRecentItem(in fileMenu: NSMenu) -> NSMenuItem? {
    fileMenu.items.first { item in
      item.identifier == Self.menuItemIdentifier || item.title == "Open Recent"
    }
  }

  private func isFileMenu(_ menu: NSMenu) -> Bool {
    guard let mainMenu = NSApp.mainMenu else { return false }

    return mainMenu.items.contains { item in
      item.title == "File" && item.submenu === menu
    }
  }

  private func move(_ item: NSMenuItem, to insertionIndex: Int, in menu: NSMenu) {
    guard let currentIndex = menu.items.firstIndex(of: item),
          currentIndex != insertionIndex
    else { return }

    let adjustedInsertionIndex = currentIndex < insertionIndex ? insertionIndex - 1 : insertionIndex
    menu.removeItem(item)
    menu.insertItem(item, at: adjustedInsertionIndex)
  }

  private func installWhenMenuIsReady() {
    guard installRetryCount < 20 else { return }

    installRetryCount += 1
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(100))
      self?.installIfNeeded()
    }
  }
}
