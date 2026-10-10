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
    for forbidden in ('sbcpurefreshrate', 'system120hz', 'dynamicsource120hz', 'hiddentext120hz', 'show120hzdiagnostics', '120hz', '120 hz'):
        if forbidden in text:
            raise AssertionError(f'{rel}: {forbidden}')
print('no 120-Hz experiment artifacts: passed')
