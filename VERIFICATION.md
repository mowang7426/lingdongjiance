# 5.09+mem2 Verification

## Scope
- Branch: `feature/text-memory-used-5.08`; base mem1 commit: `79d00c8c4965ff02615793777759e8acb1adf79a`.
- mem1 remains preserved on its original branch. mem2 changes the existing text-RAM option rather than adding a second ambiguous metric.

## Accounting
- `host_statistics64(HOST_VM_INFO64)` supplies `free_count`; `host_page_size` supplies runtime kernel page size.
- `free_count × page_size` is overflow-saturated, and used is `physicalMemory - free` clamped to `[0, physicalMemory]`.
- `physicalMemory` is `NSProcessInfo.processInfo.physicalMemory`; inactive, extra speculative and purgeable are excluded.

## Regression coverage
- Native production-boundary tests cover host failure, zero page size, truncated VM response, free-page multiplication overflow and `physical < free` clamp.
- Wiring/format coverage confirms both old configuration keys, independent default-off switches, one shared cache, fixed slot candidates `RAM0.00/0.00GB`, `RAM99.9/99.9GB`, `RAM999MB/999MB`, `RAM--`, 8–24pt normal/bold and 1–3x in UIKit CI.
- No device install, respring, kill or reboot is performed by this change.
