# SpringBoard 120 Hz request (opt-in)

Independent source implementation of the supplied static behavior description;
no MotionX binary or source is shipped. Home Settings has a default-OFF switch.
Domain: `com.yourname.sbcpufloating.highrefresh`, key:
`springBoard120HzEnabled`, Darwin event:
`com.yourname.sbcpufloating.highrefresh/changed`.

## Scope and deviations

- Filter AND runtime process/bundle checks limit injection to SpringBoard. Unlike
  the sample, UserNotificationsUIServer and SpringBoardOutofCallUI are excluded.
- Before installing any hooks, call the pre-install UIScreen getter IMP and require
  main-screen capability >=120. Earlier third-party hooks can affect this reading;
  it is not an independent physical hardware attestation.
- Only exact method return/argument encodings and count are accepted. Private
  getters are supported only if their runtime ABI exactly matches NSInteger;
  float/double/unsigned/other widths and missing methods are skipped. Range uses
  the SDK's @encode(CAFrameRateRange), never a guessed private structure.
- Enabled: screen/private compatible getters return 120; signed FPS >59 becomes
  120, including requests above 120. 0, negatives and low values pass through.
  All-zero range OR maximum>=60 OR preferred>=60 becomes {60,120,120}.
- **Additional safety deviation:** any NaN/infinity in any range field causes
  unchanged forwarding, even if another field would have triggered the sample.
  There is no added thermal-state override/monitor or power-policy change.
- Disabled: original IMP forwarding. Missing/malformed preference defaults OFF;
  failed notification registration leaves policy OFF. Exact ABI mismatch skips
  the affected method, not a fallback guessed signature.
- Constructor schedules a single main-queue installation; Darwin events refresh
  an atomic flag. No polling, tracking/replaying existing display links, or
  automatic respring. Existing requests/caches may require manual respring after
  enabling OR disabling. This is not a promise of all-app or sustained 120 FPS.
  Battery drain/heat may increase; OS thermal/power constraints still apply.

## Build and validation

`SBCPUHighRefresh` is its own Theos tweak target with its own same-name filter.
Uses standard scheme-aware Theos staging for rootless/roothide (no hard-coded
relocated runtime paths). No changes to thermal, powerd, charge or color cores.

Host tests: `python3 tests/high_refresh.py` compiles the actual production C policy
and ABI matcher; covers FPS 0/30/59/60/90/120/144/negatives and integer limits,
zero/low/boundary/non-finite ranges, OFF/unsupported combinations, exact ABI and
mismatch rejection. Also checks UI/default/domain/notification/filter contracts
and parses the real Makefile for both schemes using stub Theos includes.
**Stub wiring tests are not SDK builds or package validation.**

Required before release: build rootless and roothide with Theos/iOS SDK, inspect
both DEBs for dylib/filter placement and dependencies; verify on 120Hz and 60Hz
hardware, live on/off + manual respring recovery, actual runtime encodings,
registration failures, system low-power/thermal throttling and tweak conflicts.
An incompatible private getter may be skipped and reduce effects. No methods
loaded only after the one-time installation are subsequently retried.
