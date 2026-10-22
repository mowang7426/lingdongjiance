#!/usr/bin/env python3
"""Single-module source/package scope and real installer/production-C regression."""
from pathlib import Path
import plistlib,sys,subprocess,tempfile,os,zipfile
r=Path(__file__).resolve().parents[1]
h=r/'hello120hz';ui=(h/'Preferences/H120SettingsController.mm').read_text();core=(h/'Core/H120Hooks.mm').read_text();mk=(h/'Makefile').read_text()
expected=['SpringBoard','backboardd','replayd']
for text in ('启用调整','优选帧率','屏蔽异常','解决少数应用冲突','恢复默认','只注入系统进程','打开调试','显示系统级的调试信息','重置','注销'):
 assert text in ui,text
for key in ('wantsEnable','wantsFPS','selectedApps'):
 assert key in ui and key in core,key
assert 'H120ClientEnabled(' in core and 'H120NormalizeFPS(' in core
assert 'H120ConfirmReload(self)' in ui
assert 'TWEAK_NAME = 0hello120hz\n' in mk
assert 'Core/H120Hooks.mm Core/H120Recording.mm' in mk
assert '0hello120hzRecording_' not in mk and 'VideoToolbox' not in mk
rec=(h/'Core/H120Recording.mm').read_text();runtime=(h/'Core/H120RecordingRuntime.inc').read_text()
assert '__attribute__((constructor))' not in rec+runtime
assert core.count('__attribute__((constructor))')==1
assert 'H120EnterProcess(getprogname(), entries)' in core
assert 'H120StartRecordingRuntime' in core and 'H120StartBackboardRuntime' in core
assert 'VTCompressionSession' not in rec+runtime and 'VTSessionSetProperty' not in rec+runtime
assert not (h/'0hello120hzRecording.plist').exists()
assert 'H120InstallBackboardHooks' not in core # target-system ABI still not verified
assert '__ZNK2CA12WindowServer' not in core
assert 'com.opa334.altlist' in (r/'control').read_text()
assert 'ATLApplicationListMultiSelectionController' in ui
for rel in ('0hello120hz.plist','Preferences/Resources/DefaultInjection.plist','Preferences/Resources/AllInjection.plist'):
 f=plistlib.loads((h/rel).read_bytes())['Filter'];assert f['Executables']==expected
 assert ('com.apple.UIKit' in f['Bundles']) == ('AllInjection' in rel)
assert '@"Executables": @[@"SpringBoard", @"backboardd", @"replayd"]' in ui
zpath=Path('/var/minis/attachments/uploads/Hello120Hz源码_1.zip')
if zpath.exists():
 with zipfile.ZipFile(zpath) as z:
  for n in z.namelist():
   parts=Path(n).parts
   if n.startswith('__MACOSX') or n.endswith('/'):continue
   rel=Path(*parts[1:])
   if str(rel).startswith('Preferences/Resources/') and rel.name!='DefaultInjection.plist':assert (h/rel).read_bytes()==z.read(n),str(rel)
# Actually compile the production router and integer policy, and call real typed providers.
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)/'process'
 subprocess.run([os.environ.get('CC','cc'),'-std=c11','-Wall','-Wextra','-Werror',str(r/'tests/h120_process.c'),str(h/'Core/H120Policy.c'),'-o',str(p)],check=True)
 subprocess.run([str(p)],check=True)
# Run the actual postinst helper for both validated package-root layouts and both modes.
for layout in ('rootless','roothide'):
 for global_mode in (False,True):
  with tempfile.TemporaryDirectory() as tmp:
   b=Path(tmp)/('var/jb' if layout=='rootless' else 'jbroot-TEST');b.mkdir(parents=True)
   resource=b/'Library/PreferenceBundles/hello120hz.bundle';resource.mkdir(parents=True)
   libraries=b/'Library/MobileSubstrate/DynamicLibraries';libraries.mkdir(parents=True)
   for name in ('DefaultInjection.plist','AllInjection.plist'):
    (resource/name).write_bytes((h/'Preferences/Resources'/name).read_bytes())
   (libraries/'0hello120hz.dylib').touch()
   for suffix in ('dylib','plist'):(libraries/('0hello120hzRecording.'+suffix)).touch()
   foreign=libraries/'foreignRecording.dylib';foreign.write_bytes(b'keep')
   target=b/'var/mobile/Library/Preferences/cn.zqbb.fix120hz.injection.plist';target.parent.mkdir(parents=True)
   old={'Filter':{'Mode':'Any','Executables':['SpringBoard'],'Bundles':['com.apple.UIKit' if global_mode else 'com.apple.springboard','com.apple.Preferences']}}
   target.write_bytes(plistlib.dumps(old))
   tools=Path(tmp)/'bin';tools.mkdir()
   for name in ('chown','chmod'):
    (tools/name).write_text('#!/bin/sh\nexit 0\n');(tools/name).chmod(0o755)
   env=dict(os.environ,PATH=str(tools)+':'+os.environ['PATH'])
   for _ in range(2):subprocess.run(['sh',str(h/'install-filter.sh'),str(b)],check=True,env=env)
   assert (libraries/'0hello120hz.plist').resolve()==target.resolve()
   result=plistlib.loads(target.read_bytes())['Filter'];assert result['Executables']==expected
   assert ('com.apple.UIKit' in result['Bundles'])==global_mode
   assert not list(libraries.glob('0hello120hzRecording.*')) and foreign.read_bytes()==b'keep'
   # Reject a preference symlink instead of overwriting a foreign target.
   victim=Path(tmp)/'foreign';victim.write_bytes(b'do not touch');target.unlink();target.symlink_to(victim)
   assert subprocess.run(['sh',str(h/'install-filter.sh'),str(b)],env=env).returncode!=0
   assert victim.read_bytes()==b'do not touch'
if '--staged' in sys.argv:
 stage=Path(sys.argv[sys.argv.index('--staged')+1])
 assert list(stage.rglob('0hello120hz.dylib')) and list(stage.rglob('hello120hz.bundle'))
 for p in stage.rglob('0hello120hz.plist'):assert plistlib.loads(p.read_bytes())['Filter']['Executables']==expected
 assert not list(stage.rglob('0hello120hzRecording.dylib')) and not list(stage.rglob('0hello120hzRecording.plist'))
 for name in ('DefaultInjection.plist','AllInjection.plist'):
  matches=list(stage.rglob(name));assert matches and all(p.read_bytes()==(h/'Preferences/Resources'/name).read_bytes() for p in matches)
 helpers=list(stage.rglob('usr/libexec/hello120hz-install'));assert len(helpers)==1
 assert helpers[0].read_bytes()==(h/'install-filter.sh').read_bytes() and helpers[0].stat().st_mode & 0o111
 postinst=list(stage.rglob('postinst'));assert postinst
 assert all('"$JB/usr/libexec/hello120hz-install" "$JB"' in p.read_text() for p in postinst)
 assert list(stage.rglob('SBCPULiquidGlassBackboardd.plist'))
print('Hello original UI, single-module constructor, production routing/cadence, all-mode filter and real upgrade cleanup PASS')
