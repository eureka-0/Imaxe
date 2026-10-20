# Imaxe 1.1.0

Requires macOS 15.6 or later and an Apple Silicon Mac (arm64).

## What's new

- Check for updates from within Imaxe with Sparkle, with update preferences in Settings and EdDSA verification of update archives.
- Browse recent images and favorites in the redesigned home window, with search highlighting, list and grid layouts, persistent collections, and cached thumbnails.
- Use the adaptive image toolbar and file information popover to inspect metadata, edit file tags, and choose a file location.
- Access recently opened images from the Open Recent menu.

## Image handling and fixes

- Fix the startup failure caused by Sparkle library validation in ad-hoc signed releases while retaining Hardened Runtime.
- Improve handling of EXIF rotation and mirroring, transparent edges, ICC profiles, and image DPI. Display sizing follows the orientation-corrected pixel dimensions.
- Preserve high-bit-depth data in 16-bit PNG and TIFF display proxies, and correct memory estimates for 32-bit floating-point TIFF images.
- Preserve animated GIF frame timing and loop counts, with independent playback state for each window.
- Downsample oversized images within a retained-pixel budget. Temporary decoding allocations and total application memory can exceed that budget.
- Fix image panning, folder navigation, fit-to-screen window animation, window-size restoration, and arrow-key editing in popovers.
- Improve recovery when recent files are missing and retain zoom and window size when an image reloads after a file change.

## Format limits

- Multipage TIFF files display the first page only. The information panel reports the page count; page navigation is not available.
- Floating-point TIFF sample preservation is covered by compatibility tests. HDR screen output, HEIF gain maps, and other HDR formats are outside the verified scope.

## Installation and updates

1. Download `Imaxe-1.1.0.zip` from [this release](https://github.com/eureka-0/Imaxe/releases/tag/v1.1.0).
2. Quit Imaxe, unzip the archive, and move `Imaxe.app` to Applications, replacing the previous copy if present.
3. Open Imaxe from Applications.

This app is ad-hoc signed and is not notarized. macOS Gatekeeper may block the first launch. If you trust this download, follow Apple's [Open Anyway instructions](https://support.apple.com/en-us/102445). Do not disable system-wide security checks.

Users of version 1.0.0 must install this release manually once because that version does not include Sparkle. This release includes Check for Updates for future releases. Sparkle update signatures verify the downloaded archive; they do not replace macOS first-launch approval.

## Verification

The release candidate passed the hosted unit and UI compatibility checks on macOS 15, 26, and 27. The macOS 15 tests used products built on macOS 26 with the same Xcode 26.3 toolchain. These checks do not establish a performance guarantee or replace an end-to-end upgrade test.

The ZIP and release manifest have SHA-256 digests in `SHA256SUMS.txt`. The archive also passes EdDSA, nested code-signature, and library validation policy checks.

[Full changelog](https://github.com/eureka-0/Imaxe/compare/v1.0.0...v1.1.0)
