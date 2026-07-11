# Imaxe Progress

A long-term issue tracker. Work through items by priority; check them off or remove them when complete.

## P0 — Critical Issues

## P1 — Stability and Core Experience

### Image Loading and Memory

- [ ] Move primary image loading to URL-backed `CGImageSource` to avoid fully reading and decoding large images with `Data(contentsOf:) + NSImage(data:)`.
- [ ] Generate a downsampled first-frame preview based on window size and backing scale; request a higher LOD when zooming in.
- [ ] Limit concurrent decodes, set a cache memory budget, and clear caches under memory pressure.
- [ ] Preserve correct handling of orientation, alpha, color space, DPI, 16-bit, and multi-page images.
- [ ] Use explicit, separate loading strategies for GIF, TIFF, SVG, and static bitmaps.

### Asynchronous State Consistency

- [ ] Check request identity and cancellation after every `await`; stale requests must not commit results.
- [ ] Update the image, metadata, navigation position, and file watcher together through a single commit point.
- [ ] Distinguish `displayedURL` from `pendingURL`; reliably return to the original image when navigation to a corrupt image fails.
- [ ] Add deterministic tests for rapid A/B/C switching, delayed metadata, decode failures, and completion of stale animations.

### Thumbnails and Cache

- [ ] Move thumbnail generation out of SwiftUI `body` and the main thread, using an asynchronous service that supports cancellation and request coalescing.
- [ ] Keep Quick Look thumbnail generation asynchronous and avoid synchronous semaphore waits.
- [ ] Use temporary files and atomic replacement for cache writes; validate that cached images can be decoded on cache hits.
- [ ] Fall back to no thumbnail when the cache directory or writes fail; this must not prevent opening the primary image or terminate the app.

### Input, Limits, and Recovery

- [ ] Correctly parse `.fileURL` values from the Pasteboard without overriding `⌘V` in text inputs.
- [ ] Define and promptly clean up the lifecycle of temporary image files created from the Pasteboard.
- [ ] Limit SVG rasterization dimensions, pixel count, and memory use; return a clear error for invalid or oversized dimensions.
- [ ] Provide recoverable fallback paths when SwiftData, the cache directory, or disk writes fail.
- [ ] Hide user paths, file names, and search text in release logs by default, and cap log storage.

### Limited GitHub Distribution

- [ ] Ensure build scripts use only project-specific output and archive directories; never clean global Xcode Archives.
- [ ] Record the version, build number, and Git commit in release artifacts so the same build number never maps to different binaries.
- [ ] Distribute zip archives through GitHub Releases and state supported macOS versions and architectures in the release notes.
- [ ] Do not apply for an Apple Developer account: do not configure `Apple Development`, `Developer ID`, notarization, or stapling workflows.
- [ ] Clearly document that unsigned or ad-hoc-signed artifacts may be blocked by Gatekeeper, including installation instructions for limited distribution.
- [ ] Verify download, extraction, and first launch on a Mac without a development environment.

## P2 — Performance, Compatibility, and Experience

### Rendering and Performance

- [ ] Use Instruments to establish baselines for first visible preview time, peak RSS, and main-thread decoding across JPEG, PNG, TIFF, HEIF, WebP, GIF, and SVG.
- [ ] Confirm the bottleneck with data before introducing `CATiledLayer`; splitting into tiles while retaining full decoded frames is not sufficient.
- [ ] If tiled rendering is used, cap the tile cache, discard draw results from stale image generations, and verify the actual benefit.
- [ ] Cover cold opens, 100% and high-magnification zooming, rapid large-image switching, slow volumes, and memory-pressure scenarios.

### Files, Navigation, and Animation

- [ ] Have file watching distinguish modifications, atomic replacements, deletions, and recreations, and recover after the watcher becomes invalid.
- [ ] Support cancellation during large-directory scans and keep the current image correctly positioned in the navigation list.
- [ ] Separate animation frame state from the shared image cache; pause animations when windows are not visible or the app is inactive.

### Interaction and Accessibility

- [ ] Anchor zooming on the viewport center or pointer position, and improve panning, fit behavior, and multi-display geometry handling.
- [ ] Asynchronously prefetch file metadata and recent-image thumbnails on the home screen to avoid main-thread I/O.
- [ ] Complete keyboard navigation, VoiceOver labels, and non-trackpad interaction paths.
- [ ] Respect Reduce Motion and establish a String Catalog with localization for dynamic text.

### Testing and Builds

- [ ] Add metadata, primary-image loading, thumbnail, corrupt-file, and permission-failure tests for every registered format.
- [ ] Isolate loaders, caches, UserDefaults, and temporary directories used by tests to reduce flaky parallel tests.
- [ ] Remove machine-specific absolute paths from `buildServer.json`; document script dependencies and failure messages.
- [ ] Define the minimum macOS version and support scope for Apple Silicon and universal binaries.

## P3 — Maintenance and Polish

- [ ] Determine supported types using a combination of file extension, resource content type, and the actual ImageIO type.
- [ ] Differentiate image-loading errors: I/O, permissions, corrupt content, size limits, and cancellation.
- [ ] Show user-visible errors when clearing the cache fails in Settings; validate and normalize window-size settings.
- [ ] Reuse relative-date formatters, fix hover-state cleanup, and evaluate restoring window position and size.
- [ ] Add an `.xctestplan`, coverage reporting, and a small set of Finder, menu, and window XCUI smoke tests.
- [ ] Establish a single source of truth for Icon Composer and the legacy AppIcon.
- [ ] Maintain GitHub release notes, known limitations, and rollback instructions.

## References

- [CGImageSourceCreateThumbnailAtIndex](<https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)>)
- [kCGImageSourceShouldCacheImmediately](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcacheimmediately)
- [CATiledLayer](https://developer.apple.com/documentation/quartzcore/catiledlayer)
