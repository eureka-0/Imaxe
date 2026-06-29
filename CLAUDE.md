# CLAUDE.md

## Project Scope

Imaxe is a native macOS image viewer for fast everyday browsing on macOS 14+. Prioritize fast image opening and switching, smooth zooming and panning, low memory use for large images, common image formats, and light editing only when explicitly requested.

Do not expand into RAW editing, professional color grading, layers, batch processing, cloud sync, or AI features unless explicitly requested.

## Current Structure

- `Imaxe/ImaxeApp.swift`: app entry point, hidden-titlebar `WindowGroup`, Settings scene, appearance application, window configuration, and commands.
- `Imaxe/ContentView.swift`: owns `ImageSession`, handles file import, drag and drop, open URL events, alerts, focused scene value, and the `HomeView` / `ImageView` switch.
- `Imaxe/Core/`: image domain types: `ImageContainer`, `ImageInfo`, `ImageLoader`, and `FolderNavigator`.
- `Imaxe/Features/ImageView/`: viewer feature, including the SwiftUI host, top bar, observable viewing state, AppKit scroll / magnification bridge, image canvas, and alerts.
- `Imaxe/Features/SettingsView/`: app settings models and settings UI.
- `Imaxe/Features/HomeView.swift` and `HomeViewModel.swift`: empty state.
- `Imaxe/Shared/`: commands, constants, and shared AppKit / SwiftUI utilities.
- `Imaxe/Components/`: reusable SwiftUI/AppKit bridge components.
- `ImaxeTests/`: Swift Testing unit tests.
- `Scripts/`: scripts for testing and building the project.

## Architecture Rules

- Use SwiftUI for the app shell, settings, commands, overlays, alerts, and lightweight feature UI.
- Use AppKit through `NSViewRepresentable` for the image canvas.
- AppKit owns rendering, zooming, scrolling, clamping, fitting, drag / mouse / trackpad behavior, and window-size-sensitive geometry.
- Keep image geometry in the AppKit canvas layer when it depends on `NSScrollView`, `NSClipView`, `NSWindow`, screen, backing scale, or layout timing.
- Let `ImageSession` express user intent with state and request counters.
- Do not make SwiftUI views guess AppKit layout geometry from image pixels alone.
- Keep viewing state separate from future editing state.
- Prefer non-destructive editing models and compose edits during export.
- Use ImageIO / Core Graphics when a feature needs explicit control over thumbnail size, downsampling, cache / decode timing, metadata, orientation, incremental loading, or export.
- Keep changes tightly scoped to the requested task.

## Tooling

- Prefer tools from the `xcode-tools` MCP server when they fit the task.
- Use `DocumentationSearch` for current Apple developer documentation.
- Use `XcodeRefreshCodeIssuesInFile` for quick Swift diagnostics in a file.
- Use `ExecuteSnippet` to try temporary Swift code in the context of a project file.
- Use `BuildProject` for build-only validation when appropriate.
- Use `DocumentationSearch` liberally for Apple APIs, especially SwiftUI, AppKit, ImageIO, Core Graphics, Testing, and unfamiliar APIs.
- Always search Apple documentation first for Liquid Glass, FoundationModels, and new or changed SwiftUI representable APIs.
- Do not use Xcode tools / MCP to run tests.

## Code Style

- Types use PascalCase.
- Properties and methods use camelCase.
- Use 2-space indentation, simple imports, and clear method separation.
- Use Swift Observation (`@Observable`) for current view models / sessions.
- Prefer strong types, `let` constants, and Swift concurrency with `async` / `await`.
- Follow Swift 6 concurrency rules.
- Avoid `unsafe`, `unchecked`, and force unwrapping unless there is no reasonable safe alternative.
- Add comments only for complex or non-obvious logic.
- Avoid broad abstractions while the project is small.
- Prefer direct types that match the current feature boundary.

## Testing and Validation

- Use the Swift Testing framework for unit tests.
- Run tests with `Scripts/test.sh`. Do not use Xcode tools / MCP to run tests, because that can start LLDB.
- For build-only validation, use `BuildProject` when appropriate.
- Include small, wide, tall, large, animated, SVG, and high-zoom images in manual checks.
- For viewer changes, check Fit to Window, Fit Window to Image, trackpad scrolling at all four edges, window resizing, top bar interaction, and settings that affect initial image/window size.
