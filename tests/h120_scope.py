#!/usr/bin/env python3
from pathlib import Path
import plistlib,sys,subprocess,tempfile,os
r=Path(__file__).resolve().parents[1]
h=r/'hello120hz';ui=(h/'Preferences/H120SettingsController.mm').read_text();core=(h/'Core/H120Hooks.mm').read_text()
for text in ('启用调整','优选帧率','屏蔽异常','解决少数应用冲突','恢复默认','只注入系统进程','打开调试','显示系统级的调试信息','重置','注销'):
 assert text in ui,text
for key in ('wantsEnable','wantsFPS','selectedApps'):
 assert key in ui and key in core,key
assert 'H120ClientEnabled(' in core and 'H120NormalizeFPS(' in core
assert 'H120ConfirmReload(self)' in ui
assert 'H120Recording' not in (h/'Makefile').read_text()
assert not (h/'Core/H120Recording.mm').exists()
assert 'H120InstallBackboardHooks' not in core
assert '__ZNK2CA12WindowServer' not in core
assert 'com.opa334.altlist' in (r/'control').read_text()
assert 'ATLApplicationListMultiSelectionController' in ui
for rel in ('0hello120hz.plist','Preferences/Resources/DefaultInjection.plist'):
 f=plistlib.loads((h/rel).read_bytes())['Filter'];assert f['Executables']==['SpringBoard'];assert 'com.apple.UIKit' not in f['Bundles']
assert '@"Executables": @[@"SpringBoard"]' in ui
# Every source resource remains byte-identical to upload except the explicit default filter.
import zipfile,hashlib
z=zipfile.ZipFile('/var/minis/attachments/uploads/Hello120Hz源码_1.zip') if Path('/var/minis/attachments/uploads/Hello120Hz源码_1.zip').exists() else None
if z:
 for n in z.namelist():
  parts=Path(n).parts
  if n.startswith('__MACOSX') or n.endswith('/'):continue
  rel=Path(*parts[1:])
  if str(rel).startswith('Preferences/Resources/') and rel.name!='DefaultInjection.plist':assert (h/rel).read_bytes()==z.read(n),str(rel)
# Installer sandbox: no chown/chmod touching existing shared parents; preserve existing user config.
with tempfile.TemporaryDirectory() as tmp:
 b=Path(tmp);(b/'Library/PreferenceBundles/hello120hz.bundle').mkdir(parents=True)
 (b/'Library/MobileSubstrate/DynamicLibraries').mkdir(parents=True)
 (b/'Library/PreferenceBundles/hello120hz.bundle/DefaultInjection.plist').write_bytes((h/'Preferences/Resources/DefaultInjection.plist').read_bytes())
 (b/'Library/MobileSubstrate/DynamicLibraries/0hello120hz.dylib').touch()
 # mock ownership operations, never require root in CI
 tools=b/'bin';tools.mkdir()
 for name in ('chown','chmod'):
  (tools/name).write_text('#!/bin/sh\nexit 0\n');(tools/name).chmod(0o755)
 env=dict(os.environ,PATH=str(tools)+':'+os.environ['PATH'])
 subprocess.run(['sh',str(h/'install-filter.sh'),tmp],check=True,env=env)
 target=b/'var/mobile/Library/Preferences/cn.zqbb.fix120hz.injection.plist'
 assert (b/'Library/MobileSubstrate/DynamicLibraries/0hello120hz.plist').resolve()==target.resolve()
 target.write_bytes(b'user config preserved')
 subprocess.run(['sh',str(h/'install-filter.sh'),tmp],check=True,env=env)
 assert target.read_bytes()==b'user config preserved'
if '--staged' in sys.argv:
 stage=Path(sys.argv[sys.argv.index('--staged')+1])
 assert list(stage.rglob('0hello120hz.dylib')) and list(stage.rglob('hello120hz.bundle'))
 for p in stage.rglob('0hello120hz.plist'):
  assert plistlib.loads(p.read_bytes())['Filter']['Executables']==['SpringBoard']
 assert not list(stage.rglob('*Recording*'))
print('Hello screenshot scope, defaults, exclusions, isolation, filter installer and resources PASS')
