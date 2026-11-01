from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]; s=(r/'Tweak.xm').read_text(); h=(r/'SBCPUMemorySample.h').read_text(); m=(r/'SBCPUMemoryMetrics.h').read_text(); t=(r/'SBCPUTextMemory.h').read_text(); ui=plistlib.load((r/'sbcpuprefs/Resources/TextOnly.plist').open('rb'))['items']
assert 'Version: 5.09+mem3\n' in (r/'control').read_text()
for prefix,var,n in [('floatingTextOnly','textOnly','窗口1'),('floatingTextOnly2','textOnly2','窗口2')]:
 row=[x for x in ui if x.get('key')==prefix+'ShowMemory'][0]; assert row['cell']=='PSSwitchCell' and row['default'] is False and row['label']==n+' 剩余内存（RAM）'; assert f'{var}ShowMemory = getBoolPref(CFSTR("{prefix}ShowMemory"), NO)' in s
assert 'textOnlyMemorySample=SBCPUMemoryCachedSample();' in s and s.count('textOnlyMemorySample=SBCPUMemoryCachedSample();')==1
assert 'free_count' in h and 'inactive_count' not in h and 'NSProcessInfo.processInfo.physicalMemory' in h and 'host_statistics64' in h
assert 'used_bytes' in m and 'inactive_count' not in m and 'physical_total - free_bytes' in m
assert 'metrics.available_bytes' not in s and '(metrics.total_bytes - metrics.used_bytes) / (1024.0 * 1024.0)' in s
assert 'count < HOST_VM_INFO64_COUNT' in h and '(free_bytes >= physical_total) ? 0U' in m
for token in ['sample.total_bytes-sample.used_bytes','RAM%.0fMB','RAM%.2f%@','RAM%.1f%@','RAM--','SBCPUTextCurrentConfiguredWidth','SBCPUTextMetricAlignment']: assert token in t
assert 'SBCPUTextMemoryValue(textOnlyMemorySample)' in s and 'SBCPUMemoryCachedSample()' not in s[s.index('static CGSize layoutTextSlots'):s.index('static void applyTextOnlyTextFilter')]
assert 'slot.textAlignment=SBCPUTextMetricAlignment(i)' in s
assert 'metric==5 ? NSTextAlignmentRight : NSTextAlignmentLeft' in t
assert 'RAM%.2f/%.2f' not in t
for old1 in (False,True):
 for old2 in (False,True):
  prefs={'floatingTextOnlyShowMemory':old1,'floatingTextOnly2ShowMemory':old2}
  for key in prefs:
   row=next(x for x in ui if x.get('key')==key)
   assert row['default'] is False and prefs.get(row['key'],row['default']) is prefs[key]
assert sum('系统空闲 RAM' in x.get('footerText','') and '不额外加入 inactive' in x.get('footerText','') for x in ui)==2
print('PASS mem3 old independent switches, unchanged one-second cache, free-only display and fixed current alignment')
