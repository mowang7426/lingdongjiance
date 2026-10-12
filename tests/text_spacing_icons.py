#!/usr/bin/env python3
"""Static regression checks for 4.96 text-only typography."""
from pathlib import Path
import plistlib
root=Path(__file__).parents[1]
fmt=(root/'SBCPUTextOnlyTypography.h').read_text()
tweak=(root/'Tweak.xm').read_text()
p=plistlib.loads((root/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())
keys=[x.get('key') for x in p['items'] if isinstance(x,dict)]
assert keys.count('floatingTextOnlyLetterSpacing')==1
assert keys.count('floatingTextOnly2LetterSpacing')==1
assert 'NSKernAttributeName' in fmt and 'SBCPUTextOnlyFallbackIcon' in fmt
assert 'thermometer' in fmt and 'bolt.fill' in fmt
assert 'floatingTextOnlyLetterSpacing' in tweak and 'floatingTextOnly2LetterSpacing' in tweak
assert 'SBCPUTextOnlyAttributedRow(slot.text,slot.font,slot.textColor,' in tweak
print('text spacing and monochrome icon fallback: OK')
