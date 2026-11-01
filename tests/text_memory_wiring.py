from pathlib import Path
import plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text();ui=plistlib.loads((r/'sbcpuprefs/Resources/TextOnly.plist').read_bytes())['items']
assert 'Version: 5.09+mem1\n' in (r/'control').read_text()
for prefix,var in [('floatingTextOnly','textOnly'),('floatingTextOnly2','textOnly2')]:
 row,=[x for x in ui if x.get('key')==prefix+'ShowMemory']
 assert row['cell']=='PSSwitchCell' and row['default'] is False
 assert row['defaults']=='com.yourname.sbcpufloating' and row['get']=='getPreferenceValue:' and row['set']=='setPreferenceValue:specifier:'
 assert f'{var}ShowMemory = getBoolPref(CFSTR("{prefix}ShowMemory"), NO)' in s
 assert f'{var}ShowMemory' in s[s.index('static unsigned textSlotMask'):s.index('static void clearTextSlots')]
a=s[s.index('static void updateCPU(void) {'):s.index('static void checkHighCPU',s.index('static void updateCPU(void) {'))] if 'static void checkHighCPU' in s[s.index('static void updateCPU(void) {'):] else s[s.index('static void updateCPU(void) {'):s.index('_labelsDict[@"内存可用"].text')]
assert a.count('textOnlyMemorySample=SBCPUMemoryCachedSample();')==1
layout=s[s.index('static CGSize layoutTextSlots'):s.index('static void applyTextOnlyTextFilter(void) {')]
assert 'SBCPUTextMemoryValue(textOnlyMemorySample)' in layout
assert 'SBCPUTextMemoryConfiguredWidth(font)' in layout
assert 'SBCPUMemoryCachedSample()' not in layout
assert 'slot.realtimeInvertEnabled' in s and 'colorTextSlots(host, second)' in layout
assert 'SBCPUMemoryCachedSample();' in s[s.index('_labelsDict[@"内存可用"].text = @"读取失败";'):]
assert 'SBCPUMemoryReadWith(host,total,host_page_size,host_statistics64)' in (r/'SBCPUMemorySample.h').read_text()
print('PASS dual opt-in RAM, one shared low-frequency cache, detail panel, original color path')
