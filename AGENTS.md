# AGENTS.md

## Project Context

Imaxe is a native macOS image viewer focused on fast everyday browsing and light editing targeting macOS 14 and later. Prioritize:

- Fast image opening and switching
- Smooth zooming and panning
- Low memory use for large images
- Common image formats
- Basic editing later: rotate, flip, crop, annotations, undo/redo, JPEG/PNG export

Do not expand scope into RAW editing, professional color grading, layer-based editing, batch processing, cloud sync, or AI features unless explicitly requested.

## Architecture

Current structure:

- `ImaxeApp.swift` defines the macOS `WindowGroup`, hidden title bar window style, default size, window configurator, and app commands.
- `ContentView.swift` owns `ContentViewModel`, presents the image file importer, and switches between `HomeView` and `ImageView`.
- `Features/HomeView.swift` is the empty-state SwiftUI screen.
- `Features/Commands.swift` defines menu commands through focused scene values.
- `Features/ImageView.swift` is the core image viewing surface. It contains the SwiftUI host view, the `NSViewRepresentable` bridge, the custom `NSScrollView`/`NSClipView`, fitting requests, zoom observation, and the pixel-backed image view.
- `Features/ImageView+Topbar.swift` contains the in-window SwiftUI top bar overlay and its image/window actions.
- `Features/ImageViewModel.swift` stores view state and emits request counters for AppKit-side actions.
- `SampleImages/` contains local manual verification images. `ImaxeTests/` and `ImaxeUITests/` contain the project test targets.

Architecture rules:

- Use SwiftUI for app shell, menu commands, lightweight overlays, status UI, settings, and future panels.
- Use AppKit through `NSViewRepresentable` for the core image canvas: rendering, zooming, scrolling, clamping, fitting, drag gestures, mouse events, and trackpad interactions.
- Keep image geometry inside the AppKit canvas layer when it depends on `NSScrollView`, `NSClipView`, `NSWindow`, screen, backing scale, or layout timing.
- Let SwiftUI view models express user intent with state and request counters. Do not make view models guess AppKit layout geometry from image pixels alone.
- Keep `ImageView` as the integration boundary: SwiftUI owns presentation and actions, AppKit owns scroll view mechanics.
- Keep the top bar as a SwiftUI overlay unless the requested behavior requires real system titlebar integration. Do not introduce `NSPanel` for controls that belong inside the image window.
- `NSImage(contentsOf:)` is acceptable for the current viewer path when it performs well in practice. Do not replace it for performance reasons without measurement.
- Use ImageIO/Core Graphics when the feature needs explicit control over thumbnail/downsample size, cache/decode timing, metadata, orientation transforms, incremental loading, or export.
- Keep viewing state separate from future editing state. Prefer non-destructive editing models and compose edits during export.
- Keep changes tightly scoped to the requested task.

## Image Canvas Guidance

- `NSScrollView` should own magnification, scrolling, and viewport behavior.
- `NSClipView.constrainBoundsRect(_:)` should own centering small images and strictly clamping large images at document bounds.
- Use the image document bounds or pixel size as stable fit baselines. Avoid using the current scaled `documentView.frame.size` as the source of truth for fit calculations.
- `fitToWindow` may change magnification to fit the image in the current viewport.
- `fitWindowToImage` should resize the window to the currently displayed image size, constrained to the current screen, without changing magnification unless the user explicitly asks for that behavior.
- Prefer `window.screen ?? NSScreen.main`, `window.constrainFrameRect(_:to:)`, `contentLayoutRect`, `frameRect(forContentRect:)`, and backing-scale-aware rounding for window geometry.
- Keep scroll elasticity disabled and still clamp in the custom clip view; elasticity settings alone are not enough to guarantee no visible edge gaps.
- After animated window resizing, re-clamp scroll bounds rather than changing zoom.
- When changing AppKit layout behavior, verify small images, wide images, tall images, large images, high zoom levels, and screen-constrained window sizes.

## Tooling

Prefer tools from the `xcode-tools` MCP server whenever possible. Use:

- `DocumentationSearch` for current Apple developer documentation.
- `BuildProject` to build the Xcode project.
- `XcodeRefreshCodeIssuesInFile` for quick Swift diagnostics in a file.
- `ExecuteSnippet` to try temporary Swift code in the context of a project file.

Use `DocumentationSearch` liberally for Apple APIs, especially SwiftUI, AppKit, ImageIO, Core Graphics, Testing, and any unfamiliar API. Always search if these are referenced:

- Liquid Glass
- FoundationModels
- New or changed SwiftUI representable APIs

If an API appears in the project but is unfamiliar, assume it may be new and search Apple documentation first.

## Code Style

- Types use PascalCase; properties and methods use camelCase.
- Use `@State private var` for SwiftUI-local state and `let` for constants.
- Use the Swift Observation framework (`@Observable`) for the current view models.
- SwiftUI views conform to `View` and define UI in `body`.
- Use 2-space indentation and clear method separation.
- Keep imports simple and at the top of files.
- Prefer strong types and avoid force unwrapping.
- Prefer Swift concurrency with `async`/`await`; avoid adding Combine unless there is a clear need.
- Add comments only for complex or non-obvious logic.
- Do not add broad abstractions while the project is small. Prefer direct, explicit types that match the current feature boundary.

## Testing And Validation

- Use the Swift Testing framework for unit tests.
- For UI changes, consider adding a simple XCUI test to validate the change if it is not easily manually testable.
- Validate small Swift changes first with `XcodeRefreshCodeIssuesInFile` when practical.
- Use `BuildProject` before considering implementation work complete.
- For image canvas changes, manually test with the images in `SampleImages/` when possible:
  - image smaller than the window,
  - wide image,
  - tall image,
  - large image,
  - zoomed image larger than the screen.
- Check Fit to Window, Fit Window to Image, trackpad scrolling at all four edges, window resizing, and top bar interaction.
