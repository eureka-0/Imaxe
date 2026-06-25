# CLAUDE.md

## Project Context

Imaxe is a native macOS image viewer focused on fast everyday browsing and light editing targeting macOS 14+. Prioritize:

- Fast image opening and switching
- Smooth zooming and panning
- Low memory use for large images
- Common image formats
- Basic editing later: rotate, flip, crop, annotations, undo/redo, JPEG/PNG export

Do not expand scope into RAW editing, professional color grading, layer-based editing, batch processing, cloud sync, or AI features unless explicitly requested.

## Architecture

- `ImaxeApp.swift` — `WindowGroup`, hidden title bar, default size, window configurator, app commands
- `ContentView.swift` — owns `ContentViewModel`, file importer, switches between `HomeView` and `ImageView`
- `Features/HomeView.swift` — empty-state SwiftUI screen
- `Features/Commands.swift` — menu commands via focused scene values
- `Features/ImageView.swift` — core image viewing surface: SwiftUI host, `NSViewRepresentable` bridge, custom `NSScrollView`/`NSClipView`, fitting, zoom, pixel-backed image view
- `Features/ImageView+Topbar.swift` — in-window SwiftUI top bar overlay and image/window actions
- `Features/ImageViewModel.swift` — view state and AppKit-side request counters
- `SampleImages/` — local manual verification images
- `ImaxeTests/`, `ImaxeUITests/` — test targets

Architecture rules:

- SwiftUI for app shell, menu commands, overlays, status UI, settings, panels
- AppKit via `NSViewRepresentable` for image canvas: rendering, zooming, scrolling, clamping, fitting, drag/mouse/trackpad
- Image geometry stays in AppKit when it depends on `NSScrollView`, `NSClipView`, `NSWindow`, screen, backing scale, or layout timing
- View models express user intent via state and request counters — don't guess AppKit geometry from pixels
- `ImageView` is the SwiftUI/AppKit integration boundary
- Top bar stays a SwiftUI overlay unless system titlebar integration is required; no `NSPanel` for in-window controls
- `NSImage(contentsOf:)` is acceptable; don't replace without measurement
- Use ImageIO/Core Graphics when explicit thumbnail/downsample, cache/decode timing, metadata, orientation, incremental loading, or export control is needed
- Keep viewing state separate from future editing state; prefer non-destructive editing composed at export
- Keep changes tightly scoped to the requested task

## Image Canvas Guidance

- `NSScrollView` owns magnification, scrolling, and viewport behavior
- `NSClipView.constrainBoundsRect(_:)` owns centering small images and clamping large images at document bounds
- Use image document bounds or pixel size as fit baselines — not the current scaled `documentView.frame.size`
- `fitToWindow` — change magnification to fit image in current viewport
- `fitWindowToImage` — resize window to displayed image size, constrained to screen, without changing magnification
- Prefer `window.screen ?? NSScreen.main`, `window.constrainFrameRect(_:to:)`, `contentLayoutRect`, `frameRect(forContentRect:)`, backing-scale-aware rounding
- Keep scroll elasticity disabled; always clamp in the custom clip view
- After animated window resizing, re-clamp scroll bounds rather than changing zoom
- For canvas changes, test: small image, wide image, tall image, large image, high zoom, screen-constrained window

## Tooling

Prefer `xcode-tools` MCP server:

- `DocumentationSearch` — current Apple developer docs
- `BuildProject` — build the Xcode project
- `XcodeRefreshCodeIssuesInFile` — quick Swift diagnostics
- `ExecuteSnippet` — try temporary Swift code in project context

Use `DocumentationSearch` for any Apple API, especially SwiftUI, AppKit, ImageIO, Core Graphics, Testing, and whenever these appear:

- Liquid Glass
- FoundationModels
- New or changed SwiftUI representable APIs

## Code Style

- PascalCase for types; camelCase for properties and methods
- `@State private var` for SwiftUI-local state; `let` for constants
- Swift Observation (`@Observable`) for view models
- SwiftUI views conform to `View` with `body`
- 2-space indentation, clear method separation
- Simple imports at top of file
- Prefer strong types; avoid force unwrapping
- `async`/`await`; avoid Combine unless clearly needed
- Follow Swift 6 concurrency strictly; avoid `unsafe`/`unchecked` unless no safe alternative
- Comments only for complex or non-obvious logic
- No broad abstractions while the project is small; prefer direct, explicit types

## Testing and Validation

- Swift Testing framework for unit tests
- Consider XCUI tests for UI changes not easily manually tested
- Validate small Swift changes with `XcodeRefreshCodeIssuesInFile` first
- Run `BuildProject` before considering implementation complete
- Don't compile/run test targets unless explicitly asked; prefer single-file diagnostics + project build
- For canvas changes, manually test with `SampleImages/`:
  - image smaller than window
  - wide image
  - tall image
  - large image
  - zoomed image larger than screen
- Check: Fit to Window, Fit Window to Image, trackpad scrolling at all four edges, window resizing, top bar interaction
