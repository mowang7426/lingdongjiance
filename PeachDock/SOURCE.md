# PeachDock source and implementation status — 5.09+peach1

Base: 9eb7e4947e976da22a15c1945a598ce0f81afb63 (5.08).
Input: user-supplied Peach-2.1.8-1-source.zip, nested
INFINIDock16-Reborn/INFINIDock16-Reborn. SOURCE-SHA256SUMS records imported
input files before namespacing. LICENSE, CREDITS.md and ORIGIN.md are preserved
as supplied. Their historical authorship statements are upstream statements,
not an independent verification of every later contribution's licensing.
No images, binaries, Apelin scripts or second PreferenceLoader bundle imported.

## Development snapshot, NOT a usable Dock release

The scrolling, spring, geometry, editing, drop-preview, wrapper ownership and
bounded edge-rendering source have been isolated under SBCPUPeachDock. Pitch
uses viewport width/4 consistently for rendering and hit testing, replacing
89 pt. Owner associations use a retained weak box. Config is latched once at
SpringBoard start, in the existing preferences domain. Defaults: master OFF,
paging ON, spring ON, edge OFF. Blur retains 12 samples, at most two pending
captures per controller, a serial rendering queue and idle display-link stop.
Low power, serious/critical thermal state and accessibility policy suppress
edge effects without altering existing thermal controls.

IMPORTANT: all runtime profiles are deliberately disabled. The imported
comments describe iOS 16.2 {col,row} qq semantics; synthetic fixtures are not
independent device metadata. There is no proved Dock-only model identity,
full-group ABI evidence or verified reversible >4-icon persistence migration.
The generic maxIconCount==4 / RootFolder class heuristic was removed; its init
hook now passes through unchanged. No Hook/class_addMethod is reached on ANY
system, including 16.2 and 17.0. The integrated settings page says so and refuses
writes. This is incomplete implementation, not a claim of iOS 17 support.

## Required completion before enabling any profile

1. Evidence-backed Dock-only capacity adapter, never all four-icon models.
2. Complete preflight of every hook, callback and provider setter ABI; only
   install the entire dependent group after the complete preflight succeeds.
3. A recovery controller that retains scroll access while draining extra icons
   into validated home-screen slots, with verified persistence, rollback and
   unload/reinstall behavior. Do not delete IconState or trust automatic truncation.
4. Original INFINIDock detection before loading (including not-yet-loaded dylibs)
   and load-order testing. Current loaded-image/class detection is supplementary;
   the closed profile gate is the actual safety boundary in this snapshot.
5. Rootless/RootHide preference path/runtime tests and real-device lifecycle,
   RTL, rotation, drag/drop, edit, accessibility and >4-icon recovery validation.

The conservative user procedure for a future verified version is to move every
extra Dock icon back to the home screen while scrolling remains enabled, verify
original capacity, then disable and manually restart SpringBoard; uninstall only
after that. This procedure is not yet implemented as an enforced recovery state
machine, so capacity remains disabled. No device installation/restart is done.

Existing 5.08 floating/text inversion/CPU/charging/thermal source and filters are
unchanged. The new filter is SpringBoard-only. This module is not frame locking
and makes no 120Hz improvement claim. 5.09+peach1 sorts below 5.10; an installer
would need explicit downgrade approval. Do not install this development artifact
as a feature-complete replacement. No merge to main or official Release intended.
