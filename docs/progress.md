# Imaxe progress

Updated: 2026-10-22.
Release baseline: Imaxe 1.1.0, internal build 13.
Automatic updating, installation and migration have been accepted within the recorded scope.
Completed work and its evidence are in [Progress history](progress-history.md).

## Working agreements

- Support macOS 15.6+ on Apple Silicon / arm64 with ad-hoc signing and the existing Sparkle key; Developer ID and notarization remain outside the current scope.
- Use specific feature branches and PRs targeting main, with `macOS compatibility (unit + UI)` required before merging; small feature PRs normally use squash merge.
- CI runs on main-targeted PRs or manual dispatch, without push triggers.
  Manual dispatch can select a remote branch before it is merged; local changes must be committed and pushed to enter that run.
- Treat correctness and performance as separate acceptance tracks.
  Debug tests, AX visibility, launch-call wall time and offscreen drawing do not establish visible Release first frame, main-thread stalls or steady memory.
- Runner labels describe the tested image, not an exact macOS 15.6 installation; Intel is outside the distribution scope.
- Keep real slow-volume testing at low priority.
  An unset `IMAXE_SLOW_VOLUME_IMAGE` is pending acceptance, and an image downloaded to the internal SSD is not a slow-volume substitute.
- Write tracked documents in English and documents under `docs/agents/` in Chinese.
  Keep generated diagnostics and raw measurements in ignored directories.

## Next session: restore CI first

[CI 39722137150](https://github.com/eureka-0/Imaxe/actions/runs/39722137150) failed on develop at `a362e5d92b6dfb7441bceb9299c04ac89e8f754c`.
The macOS 26 prebuild passed, and AppKit window tests passed on all three systems.

| Runner / Xcode | Unit tests | Window tests | UI tests |
| --- | --- | --- | --- |
| macOS 15 / 26.3 | Failed: two Release Lock test definitions, three failing runs | Passed: 17 | Failed: ambiguous Clear Menu lookup |
| macOS 26 / 26.3 | Passed | Passed | Failed: the same lookup |
| macOS 27 / 27.0 | Passed | Passed | Failed: the same lookup |

- [ ] Diagnose and fix the Release Lock fixture readiness failure on macOS 15.
  Both arguments of `build and publish cannot enter an active release or remove its lock` and `terminated release frees its lock after the active tool exits` exceeded the 30-second wait for readiness.
  The lock behavior assertions had not been reached; retain child exit status and output on timeout, then determine whether the fixture exited early, stalled or was delayed by parallel tool startup.
  Do not treat concurrent compiler load as a confirmed cause or solve this only by increasing the timeout.
- [ ] Restrict `testFileMenuClearRequiresConfirmationInImageWindow` to the application's File → Open Recent submenu.
  `app.menuItems["Clear Menu"]` also matches Apple → Recent Items → Clear Menu on all three runners.
  Require a unique match within the intended submenu and preserve confirmation / cancellation checks.
- [ ] Rerun the affected checks and the full hosted matrix after the fixes.
  macOS 15 must keep using the verified prebuilt test products; all unit, window, UI and required-gate jobs must pass on the new source.
  The macOS 15 xcresult contains 117 passed test definitions, two failed definitions and one skipped slow-volume test; its device-level parameterized totals contain three failing runs.
  The complete UI result is six passed and one failed; the final four-test restart summary does not override the earlier failure.

These CI failures are the first work for the next session, ahead of new isolation assertions and further performance collection.
This analysis did not change application code, tests or workflows.

## P0: critical issues

No confirmed unresolved product P0 blocker is recorded.

## P1: stability and core experience

### P1-1: UI test isolation

Startup, window reactivation and PNG → SVG navigation were accepted by the user on 2026-10-22 and are archived.
After restoring CI:

- [ ] Add UI integration checks proving that separate test launches use separate preferences and recent records, and that cleanup affects only the current run.
  Change settings and open an image in test A, then launch B with a different test identifier and verify its independent state.
  Check production-storage sentinels only in a disposable CI account; preserve another run's data during cleanup.
  Storage-layer unit tests already pass; the current seven UI tests do not contain these dedicated integration assertions.
  A missing assertion is an evidence gap, not a confirmed isolation defect.
- [ ] Run those assertions in hosted CI and retain source SHA, environment, logs and xcresult.
  The main app creates test storage, fixtures are read directly from `images/`, and the UI runner must not assume it can create shared temporary directories.

### P1-2: Release performance baseline

The original B13 ZIP, environment manifest, seven formats × three untraced opens, JPEG recording and Time Profiler attachment are archived as preliminary evidence.
Use the current account as authorized, retain existing preferences / caches, and allow test images to enter recent records.
Keep different observer binaries, recordings and traces in separate statistical groups.

- [ ] Calibrate visible first-frame capture across the Home-to-image window transition and align input, video and frame clocks.
  The recorded JPEG window was rebound about 296 ms after input, so `first_visible_frame_ms` remains null; binding delay is not image display latency.
  Measure recording overhead against unrecorded runs.
- [ ] Complete the basic scenario matrix: JPEG, PNG, TIFF, HEIF, WebP, GIF and SVG, ten first opens per format, 100% / 4× zoom and pan, five rounds of 30 rapid switches, and fixed short-GIF playback.
  The existing 21 observations cover a fresh process entering Home for one second before its first file event; Finder launch with a document and disk-cold caching are separate conditions.
  Fix window size, ordering, input intervals and cache conditions; verify final image, orientation, alpha edges, color and interaction.
- [ ] Analyze first frame, main-thread activity and memory separately.
  The existing Time Profiler export has 421 CPU samples but no stage-aligned conclusion or waiting-thread coverage; add System Trace / Allocations evidence without resigning B13 or weakening system security.
  Report RSS and physical footprint separately, with actual sampling intervals; the current 2–12-second observation window is not proof of steady state.
- [ ] Publish correctness and performance tables, raw-data locations, rerun commands and one evidence-backed optimization target with an acceptance threshold.
  Keep individual observations, medians and ranges; distinguish displayed, cancelled and failed switches before reporting p95.
  Three runs per differently sized input do not establish format rankings, memory limits or optimization gains.

## P2: performance, compatibility and experience

### Visual and device acceptance

- [ ] Check Home, the recent-images bar, image TopBar and floating loading card on macOS 15/26, including Reduce Transparency.
  Implementation and historical regressions are archived; window / navigation acceptance does not establish final material appearance.
- [ ] Test long sessions with multiple windows, complex long GIFs and memory pressure.
  Record correctness, memory trends and stalls, including ImageIO conversion and AppKit frame representations; retained-pixel budgets and explicit cache eviction do not bound process RSS.
- [ ] Use high-zoom clarity and performance evidence to decide whether fixed proxies need higher-resolution recovery.
  If tiling is justified, verify bounded caching, stale-generation rejection and measured benefit; slicing an already decoded full image does not resolve its peak memory.
- [ ] Validate reads, first display and disconnect / reconnect on a real external disk or NAS.
  Keep this low priority; do not substitute internal-SSD fixtures or a scan gate for a slow mounted volume.
- [ ] Defer broader HDR support until it has its own scope.
  HEIF gain maps, other floating-point containers and HDR display brightness are untested; current evidence covers the existing floating-point TIFF sample and SDR AppKit rendering.

### Tooling reliability

- [ ] Resolve existing SwiftFormat findings in `ImageFileWatcher.swift`, `ImageDocument.swift`, `Coordinator.swift` and `AdaptiveToolbar.swift` separately from functional changes.
- [ ] Track macOS 15 native asset compilation independently of runtime compatibility.
  `CompileAssetCatalogVariant` failed in run `39416951796`; building on macOS 26 and executing on 15 is the supported workaround, not a toolchain fix.
- [ ] Preserve diagnostics if the Xcode 27 / macOS 27 test-host startup hang recurs.
  `Imaxe-20261021-223044.xcresult` executed no tests; its dyld file-open stall was stopped and a later targeted run passed.
  Do not count a run with no executed tests as successful coverage.

### Routine release verification

Automatic-update development is complete; retain these checks for later releases or recovery exercises.

- [ ] On the next real release, build from version-local notes, verify source and downloads, confirm ZIP / checksum-only public assets, and exercise `release.published`, public-feed convergence, seven-build retention and withdrawal recomputation.
  Verified automatic deployment evidence currently covers main push and gh-pages dispatch, not the next new release event.
- [ ] Exercise interrupted uploads, missing assets and retries with identical artifacts in a draft or test repository.
  Script tests do not replace a hosted recovery exercise; do not modify the current release for this task.

## Completed

Accepted work, scoped validation, historical CI results and superseded release records are in [progress-history.md](progress-history.md).
Current CI failures and incomplete Release performance / device acceptance remain above.

## References

- [CGImageSourceCreateThumbnailAtIndex](<https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)>)
- [kCGImageSourceShouldCacheImmediately](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcacheimmediately)
- [CATiledLayer](https://developer.apple.com/documentation/quartzcore/catiledlayer)
