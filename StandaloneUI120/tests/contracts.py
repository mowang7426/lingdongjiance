#!/usr/bin/env python3
from pathlib import Path
import plistlib,sys,struct
p=Path(__file__).resolve().parents[1]
s=(p/'Tweak.m').read_text()
assert 'UIScreen' in s and 'maximumFramesPerSecond' in s
assert 'MSHookMessageEx(UIScreen' not in s
assert s.count('MSHookMessageEx(')==1
assert 'method_getNumberOfArguments(method) != 3' in s
for encode in ('void','id','SEL','CAFrameRateRange'):
    assert '@encode('+encode+')' in s
for required in ('weakObjectsHashTable','@synchronized (link)','static __thread unsigned Bypass',
    'objc_setAssociatedObject(link, &SavedKey, nil','NSProcessInfoPowerStateDidChangeNotification',
    'NSProcessInfoThermalStateDidChangeNotification','notify_get_state','Restore();',
    'link.timestamp','now - self.start >= 3','5 * NSEC_PER_SEC','[self.link invalidate]'):
    assert required in s,required
assert s.count('displayLinkWithTarget:')==1
assert 'CADynamicFrameRateSource' not in s
assert 'SBProMotionPolicy' not in s
assert 'SBDisplayRefreshRateController' not in s
assert 'CADisableMinimumFrameDurationOnPhone' not in s
f=plistlib.loads((p/'StandaloneUI120.plist').read_bytes())
assert f=={'Filter':{'Bundles':['com.apple.springboard','com.apple.UserNotificationsUIServer','com.apple.springboard.SpringBoardOutofCallUI']}}
r=plistlib.loads((p/'prefs/Resources/Root.plist').read_bytes())
switch=[x for x in r['items'] if x.get('key')=='Enabled'][0]
assert switch['default'] is False
assert 'SUBPROJECTS += prefs' in (p/'Makefile').read_text()
assert 'Tweak.xm' not in (p/'Makefile').read_text()
if len(sys.argv)>1:
    staged=Path(sys.argv[1]); files=list(staged.rglob('*'))
    dylibs=[x for x in files if x.suffix=='.dylib']
    assert len(dylibs)==1 and dylibs[0].name=='StandaloneUI120.dylib',dylibs
    filters=[x for x in files if x.name=='StandaloneUI120.plist']
    assert len(filters)==1 and plistlib.loads(filters[0].read_bytes())==f
    assert any(x.name=='U120Prefs' and x.parent.name=='U120Prefs.bundle' for x in files)
    info=[x for x in files if x.name=='Info.plist' and x.parent.name=='U120Prefs.bundle']
    assert len(info)==1 and plistlib.loads(info[0].read_bytes())['NSPrincipalClass']=='U120Prefs'
    assert any(x.name=='U120Prefs.plist' and x.parent.name=='Preferences' for x in files)
    for binary in [dylibs[0]]+[x for x in files if x.name=='U120Prefs' and x.parent.name=='U120Prefs.bundle']:
        data=binary.read_bytes(); magic,n=struct.unpack_from('>II',data)
        assert magic==0xcafebabe,(binary,hex(magic))
        cpus=[struct.unpack_from('>II',data,8+20*i) for i in range(n)]
        assert (0x100000c,0) in cpus and any(cpu==0x100000c and subtype&0xffffff==2 for cpu,subtype in cpus),cpus
        print('PASS Mach-O arm64 + arm64e:',binary.name)
print('PASS source/config/package contracts')
