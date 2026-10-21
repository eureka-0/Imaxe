# Imaxe

[![GitHub Release](https://img.shields.io/github/v/release/eureka-0/Imaxe)](https://github.com/eureka-0/Imaxe/releases)
[![Static Badge](https://img.shields.io/badge/macOS-15.6%2B%20Apple%20Silicon-orange)](#requirements)
[![GitHub License](https://img.shields.io/github/license/eureka-0/Imaxe)](LICENSE)
[![CI](https://github.com/eureka-0/Imaxe/actions/workflows/ci.yml/badge.svg)](https://github.com/eureka-0/Imaxe/actions/workflows/ci.yml)

Imaxe is a native macOS image viewer for fast, everyday image browsing. It is built with SwiftUI and AppKit, with an emphasis on responsive image switching, smooth zooming and panning, and a lightweight browsing experience.

The project deliberately focuses on image viewing and light, non-destructive editing. It does not aim to provide RAW development, professional color grading, layer-based editing, batch workflows, cloud synchronization, or AI features.

## Requirements

- Apple Silicon based Macs (M1, M2, etc.)
- macOS 15.6 or later

## Installation

Download a ZIP from [GitHub Releases](https://github.com/eureka-0/Imaxe/releases), unzip it, quit any running copy of Imaxe, and move `Imaxe.app` to Applications.
Imaxe is ad-hoc signed and is not notarized; macOS Gatekeeper may block the first launch.
If it does, follow Apple's [Open Anyway instructions](https://support.apple.com/en-us/102445) in Privacy & Security after attempting to open the app.
Do not disable system-wide security checks.

## Release maintenance

Write release notes to an untracked Markdown file beginning with `# Imaxe <version>`.
The default location is `Build/release-notes.md`; `just build /absolute/path/to/notes.md` selects another file.
Build from a clean checkout, then publish the exact artifact from the matching remote main with `just publish`.
GitHub Release attachments contain only the ZIP and `SHA256SUMS.txt`.
The notes become the Release body and are embedded in its appcast; Markdown, appcast, and JSON manifests are not uploaded as attachments.

The publisher archives each appcast at `history/<tag>/appcast.xml` on `gh-pages` before making the Release public.
The Updates workflow verifies the public archives, retains the seven newest stable builds in the root `appcast.xml`, and explicitly deploys the complete `gh-pages` site with GitHub Actions.
Draft, prerelease, and withdrawn releases do not appear in the active feed; historical files remain in the branch and its Git history.
The production feed stays at `https://eureka-0.github.io/Imaxe/appcast.xml`.
Site files such as `index.html` and `assets/` can be added to `gh-pages`; `.nojekyll` marks the site as plain static content.

Use `just deploy-updates` to reconcile release state and deploy site changes or recover a deployment.
The public feed check waits up to ten minutes for propagation and retains HTTP headers and response bodies in the workflow diagnostics artifact.
It verifies both the canonical URL and a unique deployment probe; an HTTP 200 alone is not sufficient.

## License

Imaxe is licensed under the GPL-3.0-or-later license. Commercial use is permitted under the terms of the license, but any modifications or derivative works must also be released under the same license. See the [LICENSE](LICENSE) file for more information.
