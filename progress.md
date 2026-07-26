# Imaxe Progress

A long-term issue tracker. Work through items by priority; check them off or remove them when complete.

## P0 — Critical Issues

## P1 — Stability and Core Experience

### Image Loading and Memory

- [ ] Preserve correct handling of orientation, alpha, color space, DPI, 16-bit, and multi-page images.
- [ ] Use explicit, separate loading strategies for GIF, TIFF, SVG, and static bitmaps.

### Limited GitHub Distribution

- [ ] Include the supported macOS 15.6+ and Apple Silicon scope in generated GitHub Release notes.
- [ ] Do not apply for an Apple Developer account: do not configure `Apple Development`, `Developer ID`, notarization, or stapling workflows.
- [ ] Clearly document that unsigned or ad-hoc-signed artifacts may be blocked by Gatekeeper, including installation instructions for limited distribution.
- [ ] Verify download, extraction, and first launch on a Mac without a development environment.

## P2 — Performance, Compatibility, and Experience

### Test Reliability

- [x] Replace timing-based metadata preload coverage with an explicit document-load gate so the session test remains deterministic under parallel test load.
- [x] Verify equivalent results across repeated image loads without requiring `NSCache` to retain document identity under memory pressure.

### Rendering and Performance

- [ ] Use Instruments to establish baselines for first visible preview time, peak RSS, and main-thread decoding across JPEG, PNG, TIFF, HEIF, WebP, GIF, and SVG.
- [ ] Confirm the bottleneck with data before introducing `CATiledLayer`; splitting into tiles while retaining full decoded frames is not sufficient.
- [ ] If tiled rendering is used, cap the tile cache, discard draw results from stale image generations, and verify the actual benefit.
- [ ] Cover cold opens, 100% and high-magnification zooming, rapid large-image switching, slow volumes, and memory-pressure scenarios.

## References

- [CGImageSourceCreateThumbnailAtIndex](<https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)>)
- [kCGImageSourceShouldCacheImmediately](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcacheimmediately)
- [CATiledLayer](https://developer.apple.com/documentation/quartzcore/catiledlayer)
