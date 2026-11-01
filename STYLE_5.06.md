# 5.06 clean fixed text HUD

Based on b027c1e9026dedb851fd3afe975037279f85f7bd (charge native setter passthrough preserved).
Only the two text HUDs change. Ordinary capsules, sampling, FPS, charging, thermal and touch code are unchanged.

Example (existing metric order, illustrative values):
`CPU 24% · 1097MHz · 69FPS · BAT 82% · 37.7°C · -3mA`
No screenshot-only orange indicator, native/status labels, memory metric or other business states are added.

Each metric has its own clipped, single-line SBCPUCapsuleBackdropLabel; each middle dot has a separate label and frame. Both use the existing font/bold/colour/inversion pipeline. Text uses system monospaced digits. Slot widths are cell budgets times font size times 0.65, capped to the safe available width: CPU 10, frequency 9, FPS 6, battery 8, temperature 7, current 9, SIM1/2 10 each, upload/download 10 each. Neither slot positions nor the host size reads rendered text widths. Excessively long values clip within their slot; there is no live scaling, reflow or ellipsis.

Dot region width = max(0.55 * fontSize, 0.55 * fontSize + configuredGap). The old -15..12 gap setting remains, but negative values now stop at minimum dot space instead of overlapping metric slots. Dot labels inherit the same colour/inversion treatment and cannot receive touches. Disabled metrics and unused dots are removed, including inversion cleanup. No leading/trailing dot appears on a row.

If enabled slot budgets exceed the existing orientation-aware safe width, whole metric blocks wrap according to configuration, never live values. This is not a guarantee that all ten metrics fit one line: reduce enabled items/font size to obtain a single row on a narrow display. No live font shrinking is performed. Font, gap, toggles or orientation changes can intentionally change layout; numerical ticks cannot. An oversized individual slot is clipped to available width.

The existing second-HUD dual-network switch is retained: with both directions enabled, upload is above download in a fixed two-line terminal block with one separator before the block, none between its rows. With it disabled, both directions are horizontal where their configured budgets fit. One enabled direction occupies only one slot. The first HUD has no new dual-network switch.

Lock/passthrough ON and drag OFF, anchors, independent font/bold/gap settings and the existing colour mode are retained. No whole-view frozen touch assertion was removed or relaxed. Version assertion and old presentation-only width/string expectations were updated. Added exhaustive mask/font/portrait/landscape/dual-network dot-frame stability tests, including short, negative, three-digit FPS, very long and changing network-unit values. UIKit rendering and inversion still need real-device visual verification.
