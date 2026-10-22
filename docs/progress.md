# Imaxe progress

Updated: 2026-10-22.
Release baseline: Imaxe 1.1.0, internal build 13.
Automatic updating, installation and migration have been accepted within the recorded scope.
Completed work and its evidence are in [Progress history](progress-history.md).

## Working agreements

- Prioritize user-facing features and confirmed product defects.
  Missing supplementary test evidence alone does not block feature development.
- Support macOS 15.6+ on Apple Silicon / arm64 with ad-hoc signing and the existing Sparkle key; Developer ID and notarization remain outside the current scope.
- Use specific feature branches and PRs targeting main, with the existing `macOS compatibility (unit + UI)` check required before merging; small feature PRs normally use squash merge.
- CI runs on main-targeted PRs or manual dispatch, without push triggers.
  Local changes must be committed and pushed to enter a hosted run.
- Match verification to the changed behavior and its risks.
  Expand performance measurement for a concrete regression, a targeted optimization or an explicit measurement request.
- Runner labels describe the tested image, not an exact macOS 15.6 installation; Intel is outside the distribution scope.
- Write tracked documents in English and documents under `docs/agents/` in Chinese.
  Keep generated diagnostics and raw measurements in ignored directories.

## Current CI status

[CI 39794872986](https://github.com/eureka-0/Imaxe/actions/runs/39794872986) passed at `6cb84116a4b065b1d857631289e798353442c905`.
Every test group and coverage export passed on macOS 15 / 26 / 27; the required `macOS compatibility (unit + UI)` gate also passed.
CI repairs and the three test-execution optimizations are complete; source identities, validation scope and hosted observations are archived in [Progress history](progress-history.md#ci-repairs-and-test-execution-optimization-2026-10-22).

## Active development

No confirmed unresolved product P0 blocker is recorded.
Proceed with the next user-requested image-browsing feature or concrete product fix.
Supplementary UI isolation checks, a complete Release benchmark and broad device acceptance are deferred and do not precede that work.

High-zoom image detail recovery remains an optional product candidate from the previous roadmap.
If selected, start with a representative large image and its visible limitation, then implement the smallest useful improvement.
Broader HDR support remains outside the current feature scope.

## Verification within feature work

Reuse the existing CI and test helpers.
For changed non-trivial behavior or a confirmed bug, run the relevant suite and add a focused regression when it protects that behavior.
For UI changes, check the affected interaction; local UI automation stays limited to the affected tests under the repository rules.
Targeted performance changes need a relevant before / after comparison; general feature work does not require a new benchmark framework or a complete format matrix.

On an actual release, use the existing build / publish checks and verify the version, signature, downloadable ZIP / checksum and update feed.
Extended recovery drills and hypothetical failure campaigns remain optional follow-up work.

## Deferred work

The previous validation and maintenance plan is retained in [the deferral record](progress-history.md#deferred-validation-and-maintenance-2026-10-22).
Those items are explicitly unfinished and have no current implementation priority.
Revisit a relevant item when the affected code changes, a concrete failure occurs or the user requests that investigation.
