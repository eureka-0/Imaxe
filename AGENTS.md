# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## Project Scope

Imaxe is a native macOS image viewer for fast everyday browsing on macOS 15+. Prioritize fast image opening and switching, smooth zooming and panning, low memory use for large images, common image formats, and light editing only when explicitly requested.

Do not expand into RAW editing, professional color grading, layers, batch processing, cloud sync, or AI features unless explicitly requested.

## Tooling and Commands

- Prefer tools from the `xcode-tools` MCP server when they fit the task.
- Use `DocumentationSearch` for current Apple developer documentation, especially SwiftUI, AppKit, ImageIO, Core Graphics, Testing, and unfamiliar APIs.
- Use `XcodeRefreshCodeIssuesInFile` for quick Swift diagnostics in a file.
- Use `BuildProject` for build-only validation when appropriate.
- Always search Apple documentation first for Liquid Glass, FoundationModels, and new or changed SwiftUI representable APIs.
- Run tests with `Scripts/test.sh`. Do not use Xcode tools / MCP to run tests.

## Directory Structure

- `Imaxe.xcodeproj/`: Xcode project file.
- `Imaxe/Core/`: core models for image loading, navigating, editing, exporting, etc.
- `Imaxe/Features/`: feature-specific SwiftUI views and AppKit bridges.
- `Imaxe/Shared/`: commands, constants, and shared AppKit / SwiftUI utilities.
- `Imaxe/Components/`: reusable SwiftUI components and AppKit bridges.
- `ImaxeTests/`: Swift Testing unit tests.
- `Scripts/`: scripts for testing and building the project.

## Rules

- Use SwiftUI for the app shell, settings, commands, overlays, alerts, and lightweight feature UI. Use AppKit through `NSViewRepresentable` for the image canvas.
- AppKit owns rendering, zooming, scrolling, clamping, fitting, drag / mouse / trackpad behavior, and window-size-sensitive geometry.
- Prefer non-destructive editing models and compose edits during export.
- Use ImageIO / Core Graphics when a feature needs explicit control over thumbnail size, downsampling, cache / decode timing, metadata, orientation, incremental loading, or export.
- Keep changes tightly scoped to the requested task.
- Use 2-space indentation, simple imports, and clear method separation.
- Use Swift Observation (`@Observable`) for current view models / sessions.
- Prefer strong types, `let` constants, and Swift concurrency with `async` / `await`.
- Follow Swift 6 concurrency rules. Avoid `unsafe`, `unchecked`, and force unwrapping unless there is no reasonable safe alternative.
- Use the Swift Testing framework for unit tests.
- Do not use `@MainActor` since the project is MainActor isolated by default.
