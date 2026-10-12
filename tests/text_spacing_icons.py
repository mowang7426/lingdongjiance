#!/usr/bin/env python3
"""4.97 regression checks: compact metric labels, fixed slots, no char-kern UI."""
from pathlib import Path
import plistlib
root=Path(__file__).parents[1]
fmt=(root/'SBCPUTextOnlyTypography.h').read_text()
tweak=(root/'Tweak.xm').read_text()
policy=(root/'SBCPUTextSlotPolicy.h').read_text()
controller=(root/'sbcpuprefs/SBCPUTextOnlyController.m').read_text()
p=plistlib.loads((root/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())
keys=[x.get('key') for x in p['items'] if isinstance(x,dict)]
# The obsolete controls and implementation must stay gone; old stored values are ignored.
assert 'floatingTextOnlyLetterSpacing' not in keys
assert 'floatingTextOnly2LetterSpacing' not in keys
assert 'NSKernAttributeName' not in fmt
assert 'floatingTextOnlyLetterSpacing' not in tweak
assert 'floatingTextOnly2LetterSpacing' not in tweak
assert 'floatingTextOnlyLetterSpacing' not in controller
assert 'SBCPUTextOnlyAttributedRow(slot.text,slot.font,slot.textColor);' in tweak
# Icon fallback and both metric icons remain intact.
assert 'SBCPUTextOnlyFallbackIcon' in fmt
assert 'thermometer' in fmt and 'bolt.fill' in fmt
# Widths depend on metric identity, and x advances by a small fixed gap (zero padding).
assert 'cells[10]' in policy
assert 'x+=width;' in policy
print('4.97 compact slots/no character spacing: OK')
