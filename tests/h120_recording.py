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
rec=rec.replace('__attribute__((constructor)) static void InitializeRecording','static void InitializeRecording')
headers='\n'.join('#import "'+str(r/p)+'"' for p in ['hello120hz/Shared/H120Preferences.h','hello120hz/Core/H120Recording.h'])
native=(r/'tests/h120_recording_native.mm.in').read_text().replace('// @HEADERS@',headers).replace('// @PRODUCTION@',prefs+'\n'+rec)
if args.emit_native:args.emit_native.write_text(native)
else:
 with tempfile.TemporaryDirectory() as tmp:
  p=Path(tmp);(p/'recording.mm').write_text(native)
  subprocess.run(['clang++','-std=c++17','-fno-objc-arc','-fblocks','-framework','Foundation','-framework','AVFoundation','-framework','VideoToolbox','-framework','CoreMedia','-framework','CoreGraphics','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations',str(p/'recording.mm'),'-o',str(p/'test')],check=True)
  for mode in ['B','c','bad-block','bad-size','bad-time','bad-return','bad-flag','late']:
   subprocess.run([str(p/'test'),mode],check=True)
