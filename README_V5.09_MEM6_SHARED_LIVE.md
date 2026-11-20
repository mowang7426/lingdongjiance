# 5.09+mem6 — shared live inversion candidate

Base: mem5 `eedb71d7af144dd5ac542f03158c277162762efb`, tree `2f27d2e105b62e35c545b434a6ff35e6593b4095`.
Dedicated branch: `feature/shared-live-inversion-mem6`; Draft PR base: `feature/text-memory-used-5.08`. No changes to old PRs/main/fix5.08/mem5 branches; no Release or device installation.

## Rendering

Each pure-text HUD owns an independent `SBCPUTextSlotHost` (even if both share one UIWindow), one live `CABackdropLayer`, one filter chain and one composite alpha mask. Original slot views, layout frames, temperature/current attachments, separator dots and glyph drawing remain authoritative. Mask components reuse the mem5 production UILabel glyph renderer. Only changed glyph state is rasterized (never the screen); cached alpha coverage determines the smallest joint ink rectangle, rounded outward with one physical pixel padding and clipped to host bounds. Transparent fixed-slot margins do not enlarge the backdrop to the whole HUD. The mask reparents the original native mem5 alpha layer per visible text/dot slot, not one backdrop per slot; original bounds and drawInContext behavior are retained without bitmap scaling. A temporary glyph-only image is used solely to measure/cache alpha bounds when dirty, then released. Content scale comes from the window screen. No timer, screenshot polling or sampled background luminance.

Shared `SBCPUSharedBlurRadius` is **8.0**, versus original **50.0**. Brightness -0.285, contrast 1000, saturation 0 and invert remain in original order after Gaussian blur, including normalized edges. Live compositor background inversion remains enabled. Lower blur may preserve more nearby background texture and make contrast transitions sharper; identical visual blur output is not claimed. No new preference is added; the constant is the single shared-radius configuration point.

Typography/attributed text/attachment, bounds, scale and geometry changes update only affected cached glyphs and/or composite positioning. Same-state events perform zero mask/filter rewrites. Hidden/off/detach removes the active shared layer; show/on/reattach restores it. Normal capsule rendering remains per-label.

Factory/KVC failures or unsupported direct-child geometry disable shared rendering safely per host. Shared is detached before original per-label inversion is enabled, retaining mem5 radius 50 and glyph renderer. The per-label capability cache is independent, so one shared failure does not poison other HUDs or the compatibility path. If the original private APIs are also unavailable, the original visible UILabel fallback remains; no claim of live inversion on unsupported systems. A successful API probe cannot prove private-compositor semantics on every OS: real device validation remains required.

## Tests and artifacts

`tests/text_shared_live_uikit.sh` builds current production mask code and symbol-isolated pinned mem5 together, using only CALayer in place of the unavailable private backdrop. It checks exact alpha pixels, aggregate glyph placement, two independent HUDs, one shared backdrop per active HUD, union reduction, repeated-value zero writes, text/font/attachment/bounds/scale/geometry/hidden/off/on/window transitions and failure fallback without simultaneous renderers. Results: `test-output/text-shared-live.json`, including original host area, union frame/area and layer/mask/filter-recipe counts. Recipe counts are structural, **not real simulator CAFilter GPU counters**.

Existing mem4/mem5 glyph, FPS816, memory/layout, CPU/current, charging and thermal regressions remain in workflow. Package verifier must pass both Rootless `iphoneos-arm64` and RootHide `iphoneos-arm64e`, ten Mach-O files per package, arm64+arm64e slices, every CodeDirectory codeLimit equal to signature offset and every code-page hash, original resources/filters/settings version and no Hello/Peach experiments. CI runs macos-15 via workflow 379364365; build and artifact checks are not device GPU evidence.

No change to sampling, data values, RAM/FPS policy, charge/thermal logic, fixed-120 behavior or saved layout. No device install/respring/reboot, main merge or Release. A candidate is deliverable only after UIKit and both package verification gates pass; failures are reported, not bypassed.
