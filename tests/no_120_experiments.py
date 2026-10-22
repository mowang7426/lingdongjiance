#!/usr/bin/env python3
"""Assert the shipped product contains no 120-Hz experiment artifacts."""
from pathlib import Path
import sys
root = Path(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[1] == '--staged' else Path(__file__).resolve().parents[1]
for path in root.rglob('*'):
    if not path.is_file() or '.git' in path.parts or path.name in ('prerm', 'postinst') or path.suffix.lower() in ('.md', '.txt') or 'tests' in path.parts:
        continue
    rel = str(path.relative_to(root))
    low = rel.lower()
    if 'standaloneui120' in low or 'motionx' in low or 'refreshrate' in low:
        raise AssertionError(rel)
    try:
        text = path.read_text(errors='ignore').lower()
    except OSError:
        continue
    # Only the new, isolated source module and exact shipped bundle/filter/helper
    # are allowed. Old SBCPU/MotionX experiments remain forbidden everywhere.
    isolated = ('hello120hz' in path.parts or 'hello120hz.bundle' in path.parts or
                path.name in ('0hello120hz.dylib', '0hello120hz.plist', '0hello120hzRecording.dylib', '0hello120hzRecording.plist', 'hello120hz.plist', 'hello120hz-install'))
    if isolated:
        continue
    if rel == 'control':
        text = '\n'.join(line for line in text.splitlines() if not line.startswith('conflicts:'))
    if path.name == 'Makefile' and rel == 'Makefile':
        text = text.replace('subprojects += hello120hz', '')
    for forbidden in ('sbcpurefreshrate', 'system120hz', 'dynamicsource120hz', 'hiddentext120hz', 'show120hzdiagnostics', '120hz', '120 hz'):
        # Minimal original settings entry, not runtime code in the HUD.
        if forbidden in ('120hz', '120 hz') and (rel in ('sbcpuprefs/Resources/Root.plist', 'sbcpuprefs/SBCPUPrefsRootListController.m') or (path.name in ('Root.plist', 'SBCPUPrefs') and 'SBCPUPrefs.bundle' in path.parts)):
            continue
        if forbidden in text:
            raise AssertionError(f'{rel}: {forbidden}')
print('no 120-Hz experiment artifacts: passed')
