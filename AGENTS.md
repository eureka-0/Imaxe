# AGENTS.md

## Project Context

Imagxe is a native macOS image viewer focused on fast everyday browsing and light editing targeting macOS 14 and later. Prioritize:

- Fast image opening and switching
- Smooth zooming and panning
- Low memory use for large images
- Common image formats
- Basic editing later: rotate, flip, crop, annotations, undo/redo, JPEG/PNG export

Do not expand scope into RAW editing, professional color grading, layer-based editing, batch processing, cloud sync, or AI features unless explicitly requested.

## Architecture

- Use SwiftUI for app shell, menus, toolbar, panels, status UI, and settings.
- Use AppKit `NSView` wrapped with `NSViewRepresentable` for the core image canvas, rendering, zooming, panning, drag, mouse, and trackpad interactions.
- Use ImageIO/Core Graphics for image loading, metadata, downsampling, and export foundations.
- Keep viewing state separate from future editing state.
- Prefer non-destructive editing models; compose changes during export.
- Keep changes tightly scoped to the requested task.

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
- SwiftUI views conform to `View` and define UI in `body`.
- Use 2-space indentation and clear method separation.
- Keep imports simple and at the top of files.
- Prefer strong types and avoid force unwrapping.
- Prefer Swift concurrency with `async`/`await`; avoid adding Combine unless there is a clear need.
- Add comments only for complex or non-obvious logic.

## Testing And Validation

- Use the Swift Testing framework for unit tests.
- For UI changes, consider adding a simple XCUI test to validate the change if it is not easily manually testable.
- Validate small Swift changes first with `XcodeRefreshCodeIssuesInFile` when practical.
- Use `BuildProject` before considering implementation work complete.
