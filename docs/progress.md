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
- Write tracked documents in English and documents under `docs/agents/` in Chinese.
  Keep generated diagnostics and raw measurements in ignored directories.

## Test execution cost: hosted verification pending

[CI 39750187203](https://github.com/eureka-0/Imaxe/actions/runs/39750187203) passed the complete matrix and required gate at `2d4e769f4109b61563661d507b18a9ed61c166b4`.
Its macOS 15 tool tests still took roughly 39-43 seconds while the isolated Session suite took 1.27 seconds.

- [x] Prepare appcast, release validation, release profiling and the minimal signed-app fixture executable once before testing.
  Verify source hashes, Xcode / compiler / SDK identities and every binary digest before reuse; package the tools with macOS 15 test products.
  Normalize the host-dependent target printed by Swift's version command; keep the explicit macOS 15.6 compiler target and verify the resulting Mach-O deployment target.
  Relative source paths and a per-fixture working directory preserve the verifier's independent source Info.plist without changing its production CLI.
- [x] Run release tooling and image performance smoke tests in separate CI hosts, retaining coverage, logs and the required gate.
  Build test products once on each native runner, then execute all groups without rebuilding so coverage-mode changes do not replace their instrumentation.
- [x] Replace blocking test subprocess reads with termination callbacks, file-backed output and cancellation that waits for the owned child to exit.
  Include the test-runner cleanup fixture and preserve cleanup when release-fixture initialization fails.
- [x] Complete local group / transport checks and retain their result bundles.
  Main unit tests passed 87 definitions / 155 runs; tooling passed 11 / 11; image performance passed 4 / 4 with one skipped; Session And Navigation passed 24 / 24.
  The total is 126 passed definitions / 194 passed runs, including five new regressions; the new regressions also passed with a strict cooperative pool.
  Archive restoration, tool digests and arm64 / macOS 15.6 deployment targets were verified; coverage export passed after a strict no-coverage run using the same prebuilt products.
- [ ] Verify the optimization on fresh hosted runners; local warm timings do not establish a cloud speedup.

Implementation, validation commands and retained xcresults are documented in [test optimization evidence](agents/CI_TEST_OPTIMIZATION_2026-10-22.md).

## Previous CI repairs

Follow-up [CI 39746108043](https://github.com/eureka-0/Imaxe/actions/runs/39746108043) tested `f187a15f6f0b77800017a5a6ca753688d464cda1`.
The macOS 15 unit step reported 113 passed definitions, eight failed definitions and one skipped; all failures were Session And Navigation wait timeouts around 39 seconds.
Release Lock, its strict-pool regression, window tests and UI tests passed on macOS 15; the macOS 26 / 27 jobs passed completely.
The clustered timeouts indicate shared-host scheduling pressure; the old result does not contain a thread sample identifying the exact blocking operation.

- [x] Move Session And Navigation into its own CI test host, separate from unrelated image fixtures and release-tool compilation.
  Preserve every test, its current assertions and the 30-second wait deadline; retain a separate coverage log and xcresult.
  Keep the same verified prebuilt execution mode on macOS 15 and require this step to pass with the rest of the matrix.
- [x] Validate the new grouping on the hosted macOS 15 runner and the complete matrix in CI 39750187203.

Local follow-up validation reused build-for-testing products: the main unit group passed 97 definitions with one skipped (165 passed parameterized runs), and the isolated Session And Navigation group passed all 24 definitions / runs in about 1.3 seconds.
Together they preserve the previous 121 passed definitions / 189 passed runs; workflow YAML, shell syntax, ShellCheck and `git diff --check` passed.
See [follow-up analysis and validation](agents/CI_FAILURE_FIX_39746108043_2026-10-22.md) for the downloaded evidence and remaining diagnostic uncertainty.

[CI 39722137150](https://github.com/eureka-0/Imaxe/actions/runs/39722137150) failed on develop at `a362e5d92b6dfb7441bceb9299c04ac89e8f754c`.
The macOS 26 prebuild passed, and AppKit window tests passed on all three systems.

| Runner / Xcode | Unit tests | Window tests | UI tests |
| --- | --- | --- | --- |
| macOS 15 / 26.3 | Failed: two Release Lock test definitions, three failing runs | Passed: 17 | Failed: ambiguous Clear Menu lookup |
| macOS 26 / 26.3 | Passed | Passed | Failed: the same lookup |
| macOS 27 / 27.0 | Passed | Passed | Failed: the same lookup |

- [x] Repair the Release Lock fixture's cooperative-executor dependency locally.
  The original fixture stalled with `TEST_RUNNER_LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`; a process sample showed its sole cooperative worker blocked in the holder's pipe read.
  Start subprocesses directly, capture timestamped shell traces in separate files, and suspend while waiting for readiness or exit.
  Early exit and timeout errors retain PID, status, elapsed time, directory state and output; cleanup releases, terminates and reaps owned processes before deleting their fixture.
  Keep the original 30-second readiness deadline and all lock contention, retry, exit-code 23 / 143 and lock-removal assertions.
  New regressions cover early-exit diagnostics and timeout cleanup.
  The original failure's exact scheduling sequence remains unproven; the repaired suite and strict-pool regression passed on all three systems in CI 39746108043.
- [x] Restrict `testFileMenuClearRequiresConfirmationInImageWindow` to File → Open Recent and require one Clear Menu match.
  Locate File by its English label under the test's English launch configuration and preserve confirmation, cancellation and displayed-image checks.
- [x] Add a strict cooperative-pool Release Lock regression to every CI matrix job.
  Preserve each runner's existing execution mode, including verified prebuilt products on macOS 15, and retain a separate log / xcresult.
- [x] Rerun the full hosted matrix on the repaired source in CI 39750187203.
  macOS 15 must keep using the verified prebuilt test products; all unit, window, UI and required-gate jobs must pass on the new source.
  The grouping repair passed at `2d4e769f`; the newer test-tool optimization remains pending hosted verification.

Local validation on macOS 27.0.1 / Xcode 27.1 / arm64: the CI unit-test scope passed 121 test definitions with one skipped (189 passed parameterized runs); strict-pool Release Lock passed 8 definitions / 14 runs; the affected UI test passed 1/1.
SwiftFormat, SwiftLint, Xcode file diagnostics and `git diff --check` passed; workflow YAML and its runner-mode selection were checked locally.
The CI repairs passed hosted verification; the newer test-tool optimization remains pending above.
See [local repair evidence](agents/CI_FAILURE_FIX_2026-10-22.md) for commands, result bundles and the limits of the diagnosis.

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
