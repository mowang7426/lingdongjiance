#!/usr/bin/env python3
"""Compile pinned mem4 production renderer; replace ONLY unavailable GPU host.
The source is read from git, never a rewritten reference renderer. Runtime class
names are isolated so both implementations run in the same simulator process.
"""
import pathlib,subprocess,sys,hashlib,json
ROOT=pathlib.Path(__file__).resolve().parents[1]
BASE='fdc9a1c2083dc8b99f1a38311f7da633566efd85'
out=pathlib.Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
src=subprocess.check_output(['git','show',BASE+':SBCPUTextBackdropLabel.m'],cwd=ROOT).decode()
header=subprocess.check_output(['git','show',BASE+':SBCPUTextBackdropLabel.h'],cwd=ROOT).decode()
original=src
start=src.index('- (BOOL)createBackdrop {');end=src.index('- (void)syncBackdrop {',start)
src=src[:start]+'''- (BOOL)createBackdrop {
    _backdrop = [CALayer layer];
    _alphaMask = [SBCPUTextAlphaMask layer];
    _alphaMask.foregroundColor = UIColor.whiteColor.CGColor;
    _alphaMask.wrapped = NO;
    _alphaMask.alignmentMode = kCAAlignmentCenter;
    _alphaMask.truncationMode = kCATruncationNone;
    _backdrop.mask = _alphaMask;
    [self.layer addSublayer:_backdrop];
    return YES;
}

'''+src[end:]
# Capability flag is unused only because the real GPU host is replaced above.
src=src.replace('static BOOL SBCPUBackdropUnavailable = NO;', 'static BOOL SBCPUBackdropUnavailable = NO;')
for old,new in [('SBCPUTextBackdropLabel','SBCPUMem4BackdropLabel'),('SBCPUCapsuleBackdropLabel','SBCPUMem4CapsuleLabel'),('SBCPUTextAlphaMask','SBCPUMem4AlphaMask')]:
 src=src.replace(old,new);header=header.replace(old,new)
(out/'SBCPUMem4BackdropLabel.m').write_text(src)
(out/'SBCPUMem4BackdropLabel.h').write_text(header)
metadata={'commit':BASE,'source_sha256':hashlib.sha256(original.encode()).hexdigest(),'adaptations':['isolated Objective-C class names','CALayer host replaces private filter factory only'],'renderer_and_cache':'unmodified mem4 syncBackdrop, glyph draw and setters'}
(ROOT/'test-output').mkdir(exist_ok=True)
(ROOT/'test-output/mem4-baseline-source.json').write_text(json.dumps(metadata,indent=2)+'\n')
print('Pinned mem4 production mask:',BASE,metadata['source_sha256'])
