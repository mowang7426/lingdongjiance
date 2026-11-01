# 5.09+mem3 verification contract

Base: a1e07ff4c3b4c59c07bd9897b94b20ba5028ee07 on feature/text-memory-used-5.08.

- Free-only accounting remains in production SBCPUMemoryMetrics/Sample headers. Saturate page multiplication; cap at physical; preserve detail-panel used/total fields. Tests inject 4K/16K pages, huge inactive counts, failed/truncated host calls, zero sizes and overflow.
- Display reads exact total-used integers, never rounded display strings. MB/GB/TB/PB/EB thresholds and RAM-- tested. Both old switch keys and all four saved combinations retained.
- Current uses a configuration-only glyph budget and right alignment; shortest/longest values share frames and trailing mA edge. Dot allocation equals other metric gaps; no negative offsets or per-reading resize.
- iOS Simulator UIKit covers 8..24 normal/bold, scales 1..3, exhaustive -10000..10000 current extent, representative bitmap equality against unbounded rendering and alpha-mask public UILabel path, stable layout/network wrapping and FPS120 regression.
- CI runs on macos-15, builds Rootless and RootHide via build.yml; final artifact SHA and pagewise CodeDirectory verification recorded separately in delivery VERIFICATION.json.
- No installation, respring, kill, reboot, merge, Release, Hello or Peach restoration. No claim of real-device verification or private backdrop compositor pixel validation.
