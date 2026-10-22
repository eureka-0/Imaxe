# Imaxe progress history

Reviewed and migrated: 2026-10-22.
Open work is tracked in [progress.md](progress.md).
Test results below apply to their recorded source, environment and acceptance scope.
The failed develop run [39722137150](https://github.com/eureka-0/Imaxe/actions/runs/39722137150) is an active CI issue; earlier passing runs remain historical evidence.
Release Lock readiness and the UI Clear Menu lookup must be fixed next, while incomplete Release performance and device acceptance remain open.

## User acceptance: windows, navigation and installation

- [x] On 2026-10-22, the user confirmed startup and window reactivation behaved correctly.
  Home and Image currently disable window restoration; this acceptance does not add unreported OS versions or repeat counts.
  The foreground process with no AX window in `Imaxe-20261020-202447.xcresult` remains a historical observation, not an open window-behavior task.
- [x] On 2026-10-22, the user confirmed PNG → SVG navigation worked correctly.
  The earlier automated left-arrow failure is retained as diagnostic history and does not establish an SVG rendering regression.
- [x] On 2026-10-21, the user accepted P1-3: downloading the public ZIP, extraction, first installation and launch.
- [x] The same P1-3 acceptance covers recent records, favorites, settings, image-access permissions and manual migration from `1.0 (4)`.
  No separate installation or migration rerun was performed during archival, and no additional device or OS coverage was claimed.
  A 12 → B 13 updating has its own evidence below.

## Home, recent images and localization

- [x] Fixed cleanup deleting a record reopened during its scan.
  Snapshot record ID, path and `lastOpenedAt`, then skip changed records when applying results; preserve the reopened record and thumbnail while deleting confirmed missing records.
  The regression first reproduced the deletion, then passed all ten `RecentImagesTests` through `rtk proxy just test --skip-ui --suite RecentImagesTests --no-coverage`: `Imaxe-20261021-144613.xcresult`.
  No UI tests were run for that fix.
- [x] Fixed an old cleanup-result sheet appearing during a later clear operation by clearing its state on dismissal.
  Cleanup, cancel and confirmation UI flow passed in `Imaxe-20261021-122751.xcresult`.
- [x] `removeMissingFiles` checks availability conservatively in the background and removes only confirmed missing local files.
  Offline, network, symbolic-link and permission-uncertain records are retained; nine Recent Images regressions passed.
- [x] Expanded Simplified Chinese from 14 entries to all 183 current catalog entries, including runtime localization for the information panel and custom errors.
  Format placeholders passed validation; fixed 100% displaying as 10,000%, and validated Chinese Home, confirmation and settings UI.
- [x] Home Clear Recent Images and File-menu Clear Menu require confirmation and cover all records, including those hidden by search.
  `Imaxe-20261021-121932.xcresult` covered empty state, feedback, search, cancellation, confirmation and original-file preservation; the image-window menu confirmation also passed locally.
  The later hosted menu-query ambiguity is tracked as active CI work, without discarding this scoped local result.
- [x] Added Clean Up Missing Images before Clear, using `paintbrush`, with removed and unverifiable-retained counts.
  Cleanup does not trim valid records to the count limit or delete original images; real NAS / external-volume acceptance remains open.

On 2026-10-21, `rtk just test --no-coverage` completed 132 tests: 131 passed, zero failed and one unconfigured slow-volume test skipped.
All seven UI tests passed in `Imaxe-20261021-122914.xcresult`; Xcode MCP build, SwiftLint, ShellCheck and placeholder validation passed.
That result does not establish macOS 15/26 visual acceptance or the later hosted matrix result.

## Native material implementation

The recent-images bar and image TopBar use system `.bar` material and fine separators, following the user's Finder-header reference.
System material controls translucency; a fixed alpha is not applied.
AppKit `.titlebar` appeared too opaque in the tested host layer and was not selected for the final implementation.
The horizontal bars no longer use raised-edge Liquid Glass; the floating loading card retains native glass, with solid fallback under Reduce Transparency.

Intermediate `Imaxe-20261021-135002.xcresult` and `Imaxe-20261021-135222.xcresult` passed recent-images / settings checks but encountered an application snapshot connection interruption in image-window UI.
No material-rendering regression was established.
The final bar-material revision received build and static checks; its visual acceptance remains open in P2.
Extra screenshot-test code was withdrawn under the local-testing rule: small UI changes do not trigger UI tests, and major changes run only affected cases.

## Release profiling preparation and preliminary observations

- [x] Added `scripts/profile-release.sh` and `scripts/profile-release.swift` for artifact preparation, exact-app opening, memory sampling, target-window recording, independent traces and observer-hash grouping.
  Outputs stay in ignored `build/Performance/Release/`.
  Preparation verifies the ZIP checksum and deep code signature, records executable path / PID and refuses an existing output directory.
  Legacy appcasts without a source field have an explicit provenance limit; a present source field must match.
- [x] Used the original `1.1.0 (13)` from `2cdce9c05f36ea91e4d119cc4da35b15043c0440`.
  ZIP SHA-256 remained `485cf0f098cc0d1343252424950eeb47a8054cec360b1acfed2b88f2ae3fa24e` after collection.
  Environment: M2 Pro, 16 GiB, macOS 27.0.1, Xcode 27.1, built-in Retina at 2×; the user authorized the current account and new recent records.
  Fourteen checked preference keys were unchanged.
- [x] Completed three unrecorded / untraced first-file opens for each of seven formats, 21 observations total, all with a target AX canvas.
  Grouped observer `5614ef59aad3…` separately and retained roughly 100 ms RSS / physical-footprint CSV data and sampled peaks under `build/Performance/Release/B13-2cdce9c05f36/20261021-baseline/`.
  First frame remains null; these observations do not establish full fidelity, steady memory or interaction performance.
- [x] Confirmed JPEG content in the target-window video and final screenshot.
  After file-access authorization, attached Time Profiler to unchanged B13 and exported 421 CPU samples.
  Recording and tracing are excluded from the 21-run group; the earlier permission-blocked directory-open run is excluded rather than labeled a decoder bottleneck.
- [x] Four Release Profiling tests covered real memory / process-exit checks, SVG and legacy / current appcast validation, source mismatch, existing-output protection and summary grouping.
  `rtk proxy just test --skip-ui --suite ReleaseProfilingTests --no-coverage` passed four, failed zero: `build/TestResults/Imaxe-20261021-230045.xcresult`.
  Changed-file SwiftFormat, SwiftLint, ShellCheck, shfmt and whitespace checks passed; the phase ran no UI or hosted CI and changed no release workflow.

## Test storage and preferences

- [x] Fixed concurrent creation of shared test directories: after an already-exists error, verify ownership and a real directory; preserve other errors and symbolic-link rejection.
  Sixteen rounds of 30 contexts produced 480 preparations; the original implementation reproduced 27 race failures, and the fix passed all preparations.
  The host test validates actual run / test UUIDs rather than requiring script-only `IMAXE_TEST_RUN_ID`; runner-specific environment coverage remains, including fallback UUID support.
  `rtk proxy just test --skip-ui --suite TestStorageTests --suite ImageFidelityTests --suite RecentImagesTests --suite ImageViewTests --no-coverage` passed 45, failed zero in `build/TestResults/Imaxe-20261021-220046.xcresult`.
  Changed-file SwiftFormat / SwiftLint and diff checks passed; no UI or direct Xcode Test action was run.
- [x] Added Debug-test-only `TestStorage`, isolating the database, thumbnail cache and UserDefaults by run / test UUID.
  AppStorage, direct AppKit preference reads and related tests share the same settings source.
  The app removes its own data on exit; `scripts/test.sh` reclaims only the current run's leftovers and validates identifiers / ownership instead of deleting the shared root.
- [x] Six dedicated tests covered host isolation, independent preferences, database / cache cleanup, symbolic-link target preservation, invalid identifiers and interrupted-run cleanup.
  A simulated failure retained exit code 23 and another run's sentinel: `build/TestResults/Imaxe-20261021-213013.xcresult`, six passed and zero failed.
- [x] Full unit regression ran in two groups: `Imaxe-20261021-213247.xcresult` passed 114 with one slow-volume skip; `Imaxe-20261021-213332.xcresult` passed 17 window tests.
  Daily Debug / Release databases, caches and preference files had unchanged file counts and SHA-256 summaries before and after.
  Xcode MCP build and changed-file SwiftFormat, SwiftLint, ShellCheck, shfmt and diff checks passed.
  Four existing repository-wide SwiftFormat findings remain open in P2; UI isolation integration remains open in P1-1, while window / navigation behavior was subsequently accepted by the user.

## Repository directories and scripts

- [x] Registered lowercase `build`, `docs`, `scripts` and `images` paths in Git through intermediate renames and updated justfile, CI / Updates, scripts, fixtures and documents.
  Exact case validation passed for 120 indexed paths; Xcode's internal `Build/Products` remains unchanged, and the user's `.gitignore` edits were preserved.
  Removed rebuildable Tests / Release Build products containing stale uppercase absolute paths, preserving archives, ZIPs and SourcePackages; the clean rerun had no stale-file / allowed-root warnings.
  `rtk proxy just test --skip-ui --skip-suite ImageViewTests --no-coverage` passed 108, failed zero and skipped one slow-volume case: `build/TestResults/Imaxe-20261021-205529.xcresult`.
  ShellCheck, shfmt, SwiftLint, SwiftFormat, diff and actionlint passed, with only the official `xcode-27` label explicitly allowed by temporary actionlint configuration; no UI or hosted CI was run in that phase.

## Image loading and memory correctness

- [x] Orientation and alpha edges: EXIF 1–8 rotation / mirror corner rendering, PNG translucent colors / transparent regions / downsampled edges, and SVG transparency.
- [x] ICC and color: compare source / proxy ICC data and actual AppKit RGB rendering for sRGB and Display P3; prefer the source profile name in the information panel.
- [x] DPI and display size: retain source DPI, swap print DPI axes after 90° rotation, validate 144×72 DPI physical sizing and use orientation-corrected pixels for representation size.
- [x] Sixteen-bit proxies: check PNG / TIFF depth, alpha and non-endpoint samples; fallback is TIFF / PNG rather than JPEG / HEIC.
- [x] Multipage TIFF: display page zero only, retain total page count and show `1 / N`; distinct page sizes / contents verify AppKit does not choose another page as an alternative representation.
- [x] Keep independent GIF, TIFF-first-page, SVG and static-bitmap strategy boundaries.
  The 64 MiB retained-pixel budget accounts for depth / GIF frames, with a 16384 longest-edge limit; this is not a process RSS ceiling.
- [x] GIF proxies preserve frame count, duration and loop count; finite animation stops on the last frame, infinite animation continues, and playback state is per window.
- [x] Image delivery no longer waits for directory scanning; explicit gates cover slow scan, cancellation and stale generations, with navigation updated when scanning completes.
- [x] Release-candidate compatibility added grayscale / CMYK JPEG and TIFF, calibrated ICC, PNG / TIFF 16-bit gradients, floating-point TIFF and hand-encoded GIF disposal 2/3.
  Five tests cover nine input groups and compare original metadata, proxy data and actual AppKit rendering in `ImaxeTests/ImageCompatibilityTests.swift`; untested HDR containers / display output remain outside that evidence.

## Existing basic performance scenarios

- [x] Added an independent performance suite for seven-format cold-loader opens, 100% / 4× offscreen drawing, 30 large 5000×4000 image requests and gated directory scanning, recording correctness separately from timing.
- [x] Added two simultaneous AppKit windows, 40-frame GIF behavior, a 96-frame GIF proxy budget and equivalent loading after explicit cache clearing.
- [x] Added three independent process launches, `app.launch()` call wall time, foreground / menu availability, native file opening, visible-canvas 100% / repeated zoom, navigation and window screenshots.
  UI timing / physical footprint and short independent-app RSS samples were recorded separately.
  Launch-call wall time contains automation overhead and excludes exit waits / postlaunch checks; these Debug observations do not establish a Release visible first-frame or steady-memory baseline.

## Distribution guidance

- [x] Release-note templates include minimum OS, Apple Silicon / arm64, changes, installation and migration; generated notes still receive release-specific review.
- [x] README and templates explain ad-hoc signing / Gatekeeper, installation in Applications and Apple's Open Anyway flow, without Developer ID or notarization dependencies.

## Automatic updates and current release contract

- [x] On 2026-10-21, the user confirmed local A `1.1.0 (12)` discovered and installed B `1.1.0 (13)`.
  Sparkle's incrementing build comparison works when the marketing versions are equal.
- [x] [PR #5](https://github.com/eureka-0/Imaxe/pull/5) merged as `4f880ac5` after CI `39529968575` passed.
  The gh-pages migration retains the latest seven valid stable builds in the root feed and complete single-version XML at `history/<tag>/appcast.xml`, with formatted XML, CDATA and the same production URL.
  Main push `39530719558` and website-push repository_dispatch `39530996067` both deployed automatically.
  Distribution was removed from main, Release assets became ZIP / checksum only, and the JSON attachment was deleted.
  At that review, public `v1.1.0` was stable and published and the feed contained one `1.1.0 (13)` item.
  The old-feed server-side cause was unconfirmed; propagation-aware retries and public-byte validation were deployed.
- [x] [PR #6](https://github.com/eureka-0/Imaxe/pull/6) merged as `afe498b5` after [CI 39534814911](https://github.com/eureka-0/Imaxe/actions/runs/39534814911) passed all five prebuild, macOS 15/26/27 test and required-gate jobs.
  Notes became version-local, build output stopped generating `release.json`, and old JSON, duplicate notes and obsolete logs were removed.
- [x] Notes live at `build/Releases/Imaxe-<version>-<build>-<commit>/Imaxe-<version>.md`; `just build` no longer accepts a separate notes path.
  Missing notes create the version directory and stop before network / archive work; notes-only directories are permitted, existing artifacts / archives / conflicting provenance are protected, and notes changing during a build reject output.
  Removed obsolete JSON and checksum entries, root duplicate notes and seven old logs, preserving A/B ZIPs, original version notes and recent formal-build logs; checksums were reverified.
  Fixed Bash 3.2 empty-array handling; six `ReleaseLockTests` and three `ReleaseValidationTests` passed with zero failures in `build/TestResults/Imaxe-20261021-103747.xcresult` and `Imaxe-20261021-103925.xcresult`.
  The later macOS 15 fixture-readiness timeouts remain active CI work.
- [x] Fixed the P0 startup failure in original A `1.1.0 (11)` / B `1.1.0 (12)`.
  Ad-hoc Hardened Runtime without a Library Validation exception caused dyld to reject Sparkle, which also lacked a Team ID; the B archive reproduced exit code 134.
  The repaired A ZIP launched independently, the user confirmed installation / launch of new `1.1.0 (12)`, and A 12 → B 13 updating was accepted.
  Installation is archived under P1-3; Release performance remains open.
- [x] Added `Imaxe/Imaxe.entitlements` to Debug / Release through Xcode, retaining Hardened Runtime and adding only the Library Validation exception for the current signing model.
  The repaired A stayed `1.1.0 (12)`; Security API validation reads actual signing flags / entitlements and rejects ad-hoc hardened packages missing the exception.
  `just test --skip-ui --suite ReleaseValidationTests --no-coverage` passed two, failed zero in `build/TestResults/Imaxe-20261020-230442.xcresult`, including a real signed fixture; Swift type checking, Xcode diagnostics, SwiftFormat and SwiftLint passed.
- [x] Rebuilt repaired A from clean commit `01f9730e396f8584f94d3d860e979f886051b13b` as `1.1.0 (12)` in `build/Releases/Imaxe-1.1.0-12-01f9730e396f/`.
  ZIP SHA-256: `3a076f75a3cd41d8f763c9121822b61155ea3c99698f22c6f96db6b66a2a329c`.
  Actual ZIP EdDSA, checksums, metadata, arm64, minimum macOS 15.6, deep signing and Library Validation policy passed.
  LaunchServices opened the extracted ZIP app with normal Sparkle initialization for more than a minute; `build/LaunchChecks/A-12/launch.sample.txt` showed Sparkle loaded and the AppKit event loop running.
  That probe alone did not establish user installation, image interaction or upgrading.
- [x] After an initial tag deployment was rejected by the environment's main-only rule, the user authorized `v*` tags.
  The github-pages environment then allowed main and `v*`, with new rule ID `63728054`; this addresses environment entry, not downstream deployment or byte validation.
- [x] Migration validation passed three `ReleaseValidationTests` and three `UpdatesPipelineTests` in `build/TestResults/Imaxe-20261021-094516.xcresult` and `Imaxe-20261021-094558.xcresult`.
  Coverage includes real archive signing / provenance / metadata, numeric seven-item sorting, draft / prerelease / withdrawn filtering, duplicate builds / missing history rejection, propagation to new bytes, persistently stale content and network failure.
  Public B13 ZIP and its new history appcast passed full validation; Swift, shell, actionlint and diff checks passed.
- [x] After feed recovery, the user confirmed A `1.1.0 (12)` discovered B on 2026-10-21, despite both showing marketing version `1.1.0`.
- [x] The user confirmed local A → B automatic updating on 2026-10-21.
  That feedback did not independently establish a second Mac or every user-data category; later P1-3 acceptance has its own stated scope.
- [x] The Keychain public key matched SUPublicEDKey, valid signatures passed and changed content / wrong keys were rejected; no private key was exported or replaced.
- [x] Build / publish acquire the shared atomic directory lock before the first Xcode invocation.
  Lock contention performs no cleanup; conflict, retry and termination-release regressions passed in the recorded local runs.
- [x] Update settings observe Sparkle check / download states and allowsAutomaticUpdates; default and disabled-download synchronization tests passed.
- [x] Actual archiving exposed and fixed unintended universal output by explicitly setting `ARCHS=arm64`.
  Real ZIP architecture, version, feed, key, appcast and deep code-signature validation passed.
- [x] Anonymous inspection of the old v1.0.0 ZIP found `1.0 (4)`, minimum macOS 14.0 and no Sparkle / feed / key, establishing a one-time manual migration requirement.
- [x] Unit and UI startup arguments disable real update scheduling; settings unit tests use independent Sparkle fixtures for state transitions.

## Hosted CI and test-harness changes

- [x] PR #1's fifth run `39423318582`, source `2b9c43c3`, passed unit, independent-window and UI tests on macOS 15 / Xcode 26.3, macOS 26 / Xcode 26.3 and macOS 27 / Xcode 27.0, plus prebuild and `macOS compatibility (unit + UI)`.
  Slow-volume tests remained conditional skips, and hosted timing was not a formal Release performance result.
- [x] Required-status acceptance recorded active ruleset `25415148` requiring `macOS compatibility (unit + UI)`, restricted to GitHub Actions integration `15368` and matching the fifth run.
  Administrator `always` bypass remained; strict up-to-date enforcement was false and was not changed.
  These are the recorded configuration checks, not a fresh ruleset audit during this document migration.
- [x] PR #1's fourth run `39420553605` passed macOS 15 units with 96 passed / one skipped, 17 window tests and three UI tests; its sole remaining failure was `XCTApplicationLaunchMetric` collecting one metric on iteration zero and none on iteration one.
  xcresult confirmed separate launches and failure in metric aggregation; replacing it with wall-clock measurement passed the fifth three-system UI matrix, while the fourth run remains failed history.
- [x] Cold-launch UI measurement uses `XCTClockMetric` consistently, three rounds, explicit termination / `.notRunning` waits and timing only around `app.launch()`.
  Foreground / menu checks follow timing; the log name is `app_launch_call_wall_time`.
  Apple's documented launch behavior already terminates existing instances, so the prior failure was not attributed to reusing a process.
  These numbers are not interchangeable with the old system first-frame / responsiveness metrics.
- [x] Local `just test --ui-only --no-coverage` and `just test --test-without-building --ui-only --no-coverage` each passed four, failed zero: `build/TestResults/Imaxe-20261020-202849.xcresult` and `Imaxe-20261020-203034.xcresult`.
  Both retained three monotonic samples, execution-only mode did not compile, and diagnostics / lint passed on macOS 27.0.1 / Xcode 27.1; the fifth hosted run later passed all systems.
- [x] macOS 15 CI builds the complete app, unit and UI products on macOS 26 with Xcode 26.3 and ad-hoc signing, then transfers a tar archive preserving executable permissions, links and signatures.
  macOS 15 verifies source SHA, checkout path and Xcode version before executing all three groups with `just test --test-without-building`.
  Icon Composer assets, failing cases and floating-point assertions were retained; macOS 26/27 keep native build / test paths.
- [x] Added mutually exclusive `--build-only` and `--test-without-building` modes while retaining filters and coverage export.
  Build-only rejects test filters / coverage reporting; execution-only requires exactly one `.xctestrun`.
  The gate requires the prebuild and every matrix job; restore failure does not fall back to native macOS 15 compilation.
  PR / manual triggers and `fail-fast: false` remain.
- [x] Local build / execution separation passed `just test --build-only`, tar round-trip, deep signing of both app bundles and execution-only units / windows / UI: 96 passed with one skipped, 17 passed and four passed, totaling 117 passed / zero failed / one skipped.
  Unit identifiers formed the original 114-test union without overlap; coverage exported and execution logs contained no asset / Swift compilation.
  Evidence: `build/TestResults/Imaxe-20261020-200250.xcresult`, `Imaxe-20261020-200332.xcresult`, `Imaxe-20261020-200402.xcresult`; local macOS 27.0.1 / Xcode 27.1, with argument, Swift, shell, YAML and actionlint checks passing.
- [x] Hosted run `39423318582` validated macOS 26-built products on macOS 15, including floating-point TIFF source / proxy checks and three launch-wall-time samples.
  Native macOS 26/27 tests passed; native macOS 15 asset compiler stability remains a separate open issue.
- [x] In PR #1's second run `39414212147`, macOS 15 `NSBitmapImageRep.colorAt` returned blue 1.0 instead of the expected 1.5 for floating-point TIFF.
  Direct source / proxy float checks plus AppKit rendering passed units on all three systems in fourth run `39420553605`, without weakening the out-of-range sample requirement.
- [x] Float32 checks read Core Graphics `dataProvider` bytes with row stride, component byte order and channel layout.
  Source and proxy TIFF each check `[0.25, 0.5, 1.5]` with 0.001 tolerance, 32-bit / floating flags, 16-byte RGBA budgeting and actual AppKit rendering.
  macOS 15 is neither skipped nor given wider tolerance; clipping still reports source / proxy and channel.
- [x] Local `just test --skip-ui --suite ImageCompatibilityTests --no-coverage` passed five tests over nine groups: `build/TestResults/Imaxe-20261020-193734.xcresult`, with diagnostics and lint passing.
  Two temporary-signing host startup hangs were stopped and excluded; the new macOS 15 checks later passed in the fourth hosted run.
- [x] macOS 26 toolchain mixing and macOS 27 window-test timeouts from first run `39393986174` did not recur in second / third runs, which passed those jobs.
  macOS 15 asset / window / UI execution passed in the second run, but the asset agent crashed again in the third; an occasional compile success was not accepted as a toolchain fix.
- [x] CI now synchronizes `xcode-select` with `DEVELOPER_DIR`, clears xcrun lookup caches and passes `TEST_RUNNER_DEVELOPER_DIR` to test hosts.
  The second run confirmed macOS 15 asset compilation and macOS 26 release validation under the chosen toolchain.
- [x] `ImageViewTests` uses Swift Testing `.serialized`, and CI separates it from other units through `--suite` / `--skip-suite`.
  Decoding, performance fixtures and release-tool compilation no longer share that host with window animations; assertions and timeouts remain.
  Build failures with zero tests still retain summaries and complete build logs.
- [x] Local CI repair verification passed 17 window tests and 96 other units with one slow-volume skip and exported coverage.
  The groups covered the original 114 identifiers without overlap; build-failure replay retained two summaries / build logs and still returned failure.
  Evidence: `build/TestResults/Imaxe-20261020-190916.xcresult`, `build/TestResults/Imaxe-20261020-191152.xcresult`; Xcode diagnostics, Swift / shell formatting, workflow and diff checks passed.
- [x] Local UI run `build/TestResults/Imaxe-20261020-191250.xcresult` timed out enabling automation and executed no tests; read-only inspection found automation disabled and requiring user authentication, without changing security settings.
  Retry `build/TestResults/Imaxe-20261020-191533.xcresult` passed four, failed zero; combined units / UI passed 117 with one skipped.
  Two earlier dyld-file-open host hangs were stopped and excluded; preserving the old derived directory and rebuilding passed, followed by the fifth hosted matrix.
- [x] Added CI for main-targeted PRs and manual dispatch only, without push triggers.
  ARM64 macos-15 / macos-26 use Xcode 26.3 and xcode-27 uses stable Xcode 27.0.
  `just test` runs units with coverage and UI separately; `fail-fast: false` retains independent system evidence.
  Temporary ad-hoc signing needs no developer certificate; environment, logs, summaries and full xcresult artifacts are retained for 14 days.
  Job `macos_compatibility_gate` exposes stable check name `macOS compatibility (unit + UI)` and succeeds only when the entire matrix succeeds.
- [x] Local CI-entry testing with the same temporary signing configuration passed 113 units with one skip and four UI tests, zero failures, with coverage export.
  Evidence: `build/TestResults/Imaxe-20261020-155435.xcresult`, `build/TestResults/Imaxe-20261020-155514.xcresult`, on macOS 27.0.1 / Xcode 27.1; this alone did not establish hosted-system coverage.
- [x] Matrix YAML, events, runner / Xcode pairs, fail-fast behavior, gate dependencies, shell syntax and diff checks passed.
  actionlint 1.7.12 lacked the official `xcode-27` label; a temporary configuration allowed only that label, with other checks retained, and validated CI / Updates.
- [x] PR #1's fifth matrix run exercised native file panels, UI automation and the test host, and made the workflow available on the default branch.
  Required-check and administrator-bypass behavior were recorded as above.
  Manual dispatch was not part of that original acceptance; the later develop dispatch `39722137150` ran and failed, and is tracked in the active roadmap.
- [x] Replaced timing-dependent metadata-preload coverage with an explicit document-load gate for deterministic parallel session tests.
- [x] Repeated image loads verify equivalent results without requiring `NSCache` to preserve document identity under memory pressure.
- [x] Retained reload-equivalence tests and added explicit-cache-clear checks for metadata, dimensions and rendered pixels, without object-identity or eviction-timing assumptions.
- [x] Moved release-validation compilation and child waits off the main thread, retaining window assertions and timeouts; the recorded complete regression passed 109 tests.
- [x] The 2026-10-20 candidate regression through `just test --no-coverage` after file-path repair passed 117, failed zero and skipped one unconfigured real-slow-volume test out of 118.
  All four UI tests, changed-file SwiftFormat / SwiftLint and diff checks passed: `build/TestResults/Imaxe-20261020-153504.xcresult`.
- [x] At that stage the test entry copied fixtures into ignored Build output, waited for native file-panel controls and kept screenshots within the app window.
  High-zoom overflow did not capture the whole display; window / animation assertions and timeouts were retained.
  The later lowercase-path and app-owned fixture-storage changes supersede that fixture-location detail.

## Other validated repairs

- [x] Fixed lost characters while typing file-panel paths by pasting complete text after saving the clipboard and waiting for the field value.
  Restore the previous clipboard only if another app has not replaced it during the operation.
- [x] A later Return confirmation reproduced an `openAndSavePanelService` text-input crash after successful paste.
  Waiting for and double-clicking the matching native completion row passed four UI cases with zero failures in `build/TestResults/Imaxe-20261020-153322.xcresult`; path, opened image, zoom and navigation assertions remain.
- [x] Fixed underestimated floating-point TIFF memory budgets: proxy sizing and cache estimates share depth-aware RGBA cost, using 16 bytes per pixel for 32-bit input.
  Source depth, channel values above 1.0 and AppKit reference rendering regressions passed.
- [x] Moved ImageCollectionView state / default construction into its initializer and created ImageSession metadata work separately.
  Seven generic-isolation warnings and one weak-capture warning were removed; Xcode build and diagnostics were warning-free.
- [x] Merged adjacent ImageCollectionView guards with identical outcomes while retaining short-circuit order; SwiftFormat repeatedGuard passed.

## Superseded releases and withdrawn artifacts

Original A 11 / B 12 were withdrawn for startup failure and replaced by repaired A 12 / B 13.
The manifest-based, three-asset and five-asset contracts below are historical; PR #5 / #6 established the current ZIP / checksum-only public contract.
Historical uppercase Build / Distribution paths identify old evidence and are not current maintenance instructions.

- [x] An intermediate contract uploaded ZIP, `release.json` and `SHA256SUMS.txt`, keeping Markdown / appcast local and embedding feed data in the manifest.
  Titles / notes used marketing versions and build numbers stayed internal; three release-validation cases, lock tests and a real A three-asset copy passed in `build/TestResults/Imaxe-20261020-232844.xcresult`, with Swift / shell / Updates checks passing.
- [x] Under user authorization, faulty `v1.1.0` returned to draft, retaining its tag and five assets.
  Updates `39442929884` restored an empty feed: anonymous HTTP 200, zero items and matching source bytes; the faulty ZIP URL returned 404.
  At the user's request old faulty outputs and about 4.4 GiB of obsolete Build data were deleted; diagnosis remained in ignored `docs/agents/SPARKLE_LAUNCH_FAILURE_2026-10-20.md`.
- [x] On 2026-10-20, anonymous `https://eureka-0.github.io/Imaxe/appcast.xml` returned HTTP 200, `application/xml`, one channel and zero items, matching `Distribution/appcast.xml`.
  Empty-feed SHA-256: `91ad5658dd8d8dfa61e843b3d2445fee3997346d5854d67114060ecf676bf1bb`.
  This established feed accessibility / deployment only.
- [x] PR #3 CI `39449750682` passed all five jobs and merged by authorization as `2cdce9c05f36ea91e4d119cc4da35b15043c0440`.
  Clean main, matching the remote, produced repaired `1.1.0 (13)` at `build/Releases/Imaxe-1.1.0-13-2cdce9c05f36/` with ZIP SHA-256 `485cf0f098cc0d1343252424950eeb47a8054cec360b1acfed2b88f2ae3fa24e`.
  Signing, EdDSA, metadata and provenance passed; the independently extracted final app loaded Sparkle and entered AppKit's main loop, recorded at `build/LaunchChecks/B-13/launch.sample.txt`.
  After safely moving the withdrawn tag, v1.1.0 was republished at 2026-10-20 23:52:43 Asia/Shanghai with ZIP, manifest and checksum assets; public bytes matched and passed validation.
- [x] Release-event run `39452440735` uploaded the correct B13 appcast, but public Pages stayed on the old empty feed through 12 byte-check attempts.
  Main manual run `39453494899`, with `release_tag=v1.1.0`, passed.
  At 2026-10-21 00:02 Asia/Shanghai, canonical and deployment-query URLs both returned HTTP 200, 4330 bytes and one update with `sparkle:version=13` / `sparkle:shortVersionString=1.1.0`, matching the manifest's appcast.
  SHA-256: `541a9ffd7e1d31740321ac8459de451dfd0b1b206186c31482a31eb19b07590b`.
  A's earlier latest-version message occurred before feed recovery and did not establish a build-comparison defect.
- [x] On 2026-10-19, verified a public repository and anonymous old-ZIP download, enabled Pages Actions publishing and prepared `SUFeedURL`, the initial empty feed and deployment workflow; first hosted deployment followed the next day.
- [x] The earlier publisher already verified artifact checksums, EdDSA, package metadata, exact source, online / manifest build progression, draft-asset readback and identical-artifact recovery.
  It did not automatically switch branches or overwrite differing assets; manifest-specific details were subsequently superseded.
- [x] PR #1 merged to main on 2026-10-20 as `f66f4c3d`, and its remote develop branch was deleted.
  Updates `39427222348` deployed the initial empty feed with anonymous HTTP / XML acceptance; later `7459e278` added only a README CI badge.
  This historical branch deletion does not describe the later recreated develop branch.
- [x] Original internal A came from clean main `7459e278aff8afffd55b2d591a7e9439553aba56`, matching the remote, through `just build`.
  It was `1.1.0 (11)`, arm64, minimum macOS 15.6, with feed, key, EdDSA, deep signing and checksums verified, without a tag or Release.
  Directory: `build/Releases/Imaxe-1.1.0-11-7459e278aff8/`; ZIP SHA-256: `bbe211f94d84c6d565eb3e534ec4c660b1406368b891773c8513ff1a4763eaf4`.
  Older 9/10/11 ZIPs lacking feed / key were excluded from A/B use; this original A was later withdrawn for startup failure.
- [x] Initial release preparation set app Debug / Release to `1.1.0 (12)` from build 11, leaving test-target versions unchanged.
  A initially stayed 11, while app identity, update key, feed and signing model remained consistent; repaired A / B later replaced these build assignments.
- [x] PR #2 CI `39435527143` passed, then merged by authorization with a merge commit retaining `5a810229` and `a1e9f0c5`.
  Clean main `5ff38f1126229db9d2045b81b5e7454aed295258`, matching the remote, produced original B `1.1.0 (12)` at `build/Releases/Imaxe-1.1.0-12-5ff38f112622/`.
  ZIP SHA-256: `8963918a411210c3ce8325728c7511c664911b19dbf0863a7314c868c0c4e41b`; checksums, EdDSA, metadata and deep signing passed, before the later launch failure was discovered.
- [x] The user authorized publishing that original B; English notes and their checksum were updated while keeping the ZIP unchanged.
  `just publish` made stable `v1.1.0` public at 2026-10-20 22:24:06 Asia/Shanghai, with the tag on that B source, five assets uploaded / read back and matching Release body / notes.
  Publishing itself did not establish performance, installation or upgrading acceptance.
- [x] Anonymous ZIP, Markdown, appcast, manifest and SHA256SUMS downloads matched local assets and passed `scripts/validate-release.swift` checks for checksums, EdDSA, appcast, architecture and signing.
  Verified copies were at `build/PublicVerification/v1.1.0/`.
- [x] Main Updates `39439124403` recovered from the original Pages environment-rule rejection and passed stable-feed / deployment / public-byte checks.
  The canonical URL returned HTTP 200 and one `1.1.0 (12)` update with minimum macOS 15.6, arm64 and correct download / notes links, matching the Release appcast.
  SHA-256: `f92c5e556a3a2c9242358631a2817f745faa6f83c44b0f187aac7f7becc21855`.
  This was one manual recovery, not acceptance of arbitrary interruption recovery or actual upgrading.
