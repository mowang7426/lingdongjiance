#!/usr/bin/env python3
"""Compile and execute the shipped ObjC++ recording body with only platform adapters."""
from pathlib import Path
import re,subprocess,tempfile,argparse
r=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--emit-native',type=Path);args=a.parse_args()
prefs=(r/'hello120hz/Shared/H120Preferences.mm').read_text()
prefs=re.sub(r'#if defined\(THEOS_PACKAGE_SCHEME_ROOTHIDE\)\n#include <roothide.h>\n#else\n#include <rootless.h>\n#endif','',prefs)
prefs=prefs.replace('#import "H120Preferences.h"','')
rec=(r/'hello120hz/Core/H120Recording.mm').read_text().replace('#include "H120RecordingRuntime.inc"',(r/'hello120hz/Core/H120RecordingRuntime.inc').read_text())
rec=rec.replace('#import "H120Recording.h"','').replace('#import "../Shared/H120Preferences.h"','').replace('#import <substrate.h>','')
rec=rec.replace('#include "../Shared/H120RecordingDiagnostics.h"', '#include "'+str(r/'hello120hz/Shared/H120RecordingDiagnostics.h')+'"')
# Include the actual sole constructor body too; only substrate/platform adapters
# and automatic invocation are substituted, never its process routing decisions.
hooks=(r/'hello120hz/Core/H120Hooks.mm').read_text().replace('#import <substrate.h>','')
hooks=hooks.replace('__attribute__((constructor)) static void H120Initialize','static void H120Initialize')
hooks=re.sub(r'(#(?:import|include) )"([^"]+)"', lambda m: m[1]+'"'+str((r/'hello120hz/Core'/m[2]).resolve())+'"', hooks)
policy=(r/'hello120hz/Core/H120Policy.c').read_text().replace('#include "H120Policy.h"','#include "'+str(r/'hello120hz/Core/H120Policy.h')+'"')
headers='\n'.join('#import "'+str(r/p)+'"' for p in ['hello120hz/Shared/H120Preferences.h','hello120hz/Core/H120Recording.h'])
native=(r/'tests/h120_recording_native.mm.in').read_text().replace('@DIAGNOSTIC_HEADER@',str(r/'hello120hz/Shared/H120RecordingDiagnostics.h')).replace('// @HEADERS@',headers).replace('// @PRODUCTION@',prefs+'\n'+rec+'\n'+hooks+'\n'+policy)
if args.emit_native:args.emit_native.write_text(native)
else:
 with tempfile.TemporaryDirectory() as tmp:
  p=Path(tmp);(p/'recording.mm').write_text(native)
  subprocess.run(['clang','-std=c11','-fblocks','-c',str(r/'hello120hz/Shared/H120RecordingDiagnostics.c'),'-o',str(p/'diagnostics.o')],check=True)
  subprocess.run(['clang++','-std=c++17','-fno-objc-arc','-fblocks','-framework','Foundation','-framework','QuartzCore','-framework','AVFoundation','-framework','CoreMedia','-framework','CoreGraphics','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations',str(p/'recording.mm'),str(p/'diagnostics.o'),'-o',str(p/'test')],check=True)
  for mode in ['B','c','bad-block','bad-size','bad-time','bad-return','bad-flag','late',
               'vsync-bad-return','vsync-bad-arg','vsync-bad-count','vsync-missing-setter',
               'vsync-missing-key','vsync-key-type','vsync-exception']:
   subprocess.run([str(p/'test'),mode],check=True)
