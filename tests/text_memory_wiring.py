from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]; s=(r/'Tweak.xm').read_text(); h=(r/'SBCPUMemorySample.h').read_text(); m=(r/'SBCPUMemoryMetrics.h').read_text(); t=(r/'SBCPUTextMemory.h').read_text(); ui=plistlib.load((r/'sbcpuprefs/Resources/TextOnly.plist').open('rb'))['items']
assert 'Version: 5.09+mem2\n' in (r/'control').read_text()
for prefix,var,n in [('floatingTextOnly','textOnly','窗口1'),('floatingTextOnly2','textOnly2','窗口2')]:
 row=[x for x in ui if x.get('key')==prefix+'ShowMemory'][0]; assert row['cell']=='PSSwitchCell' and row['default'] is False and row['label']==n+' 内存占用（RAM）'; assert f'{var}ShowMemory = getBoolPref(CFSTR("{prefix}ShowMemory"), NO)' in s
assert 'textOnlyMemorySample=SBCPUMemoryCachedSample();' in s and s.count('textOnlyMemorySample=SBCPUMemoryCachedSample();')==1
assert 'free_count' in h and 'inactive_count' not in h and 'NSProcessInfo.processInfo.physicalMemory' in h and 'host_statistics64' in h
assert 'used_bytes' in m and 'inactive_count' not in m and 'physical_total - free_bytes' in m
for sample in ['RAM0.00/0.00GB','RAM99.9/99.9GB','RAM999MB/999MB','RAM--']: assert sample in t
assert 'SBCPUTextMemoryValue(textOnlyMemorySample)' in s and 'SBCPUMemoryCachedSample()' not in s[s.index('static CGSize layoutTextSlots'):s.index('static void applyTextOnlyTextFilter')]
print('PASS mem2 dual old-key opt-in, one cache, Inspector free-only used/total and expanded fixed slot')
