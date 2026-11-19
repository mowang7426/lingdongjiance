#!/usr/bin/env python3
"""Verify shipped DEBs, all Mach-O slices, CodeDirectory page hashes and SHA256."""
import argparse, hashlib, json, pathlib, plistlib, struct, subprocess, tempfile

MAGICS={bytes.fromhex('cffaedfe'),bytes.fromhex('cafebabe')}
def verify_macho(path):
    data=path.read_bytes(); magic=struct.unpack_from('>I',data)[0]
    if magic==0xcafebabe:
        n=struct.unpack_from('>I',data,4)[0]
        assert n==2 and 8+20*n<=len(data),path
        slices=[]
        for i in range(n):
            cpu,sub,start,size,align=struct.unpack_from('>IIIII',data,8+20*i)
            assert 0<=align<32 and start%(1<<align)==0 and start>=8+20*n and 32<=size<=len(data)-start,path
            slices.append((cpu,sub,start,size))
        ordered=sorted(slices,key=lambda s:s[2]); assert ordered[0][2]+ordered[0][3]<=ordered[1][2],path
    else:
        assert data[:4]==bytes.fromhex('cffaedfe'),path
        cpu,sub=struct.unpack_from('<II',data,4);slices=[(cpu,sub,0,len(data))]
    result=[]
    for cpu,sub,start,size in slices:
        b=data[start:start+size];assert struct.unpack_from('<I',b)[0]==0xfeedfacf,path
        assert struct.unpack_from('<II',b,4)==(cpu,sub),path
        ncmds,cmdbytes=struct.unpack_from('<II',b,16); end=32+cmdbytes;pos=32;sig=None
        assert end<=len(b) and ncmds<=cmdbytes//8,path
        for _ in range(ncmds):
            assert pos+8<=end,path
            cmd,sz=struct.unpack_from('<II',b,pos);assert sz>=8 and sz%8==0 and pos+sz<=end,path
            if cmd==0x1d:
                assert sig is None and sz==16,path
                sig=struct.unpack_from('<II',b,pos+8)
            pos+=sz
        assert pos==end,path
        assert sig,('missing LC_CODE_SIGNATURE',path)
        off,length=sig
        assert end<=off and 12<=length==len(b)-off,path
        blob=b[off:off+length];sm,sl,count=struct.unpack_from('>III',blob)
        assert sm==0xfade0cc0 and 12+8*count<=sl<=length and count>0,path
        dirs=[]; regions=[]; types=set()
        for i in range(count):
            typ,ofs=struct.unpack_from('>II',blob,12+8*i)
            assert typ not in types and 12+8*count<=ofs<=sl-8,path
            types.add(typ)
            cm,cl=struct.unpack_from('>II',blob,ofs)
            assert 8<=cl<=sl-ofs,path
            regions.append((ofs,ofs+cl))
            is_cd_slot=typ==0 or 0x1000<=typ<0x1005
            assert is_cd_slot==(cm==0xfade0c02),path
            if not is_cd_slot:continue
            cd=blob[ofs:ofs+cl]
            assert cl>=44,path
            _,_,version,flags,hashoff,identoff,nspecial,ncode,limit=struct.unpack_from('>9I',cd)
            hsize,htype,platform,psize=struct.unpack_from('4B',cd,36)
            min_header=max(n for v,n in ((0,44),(0x20100,48),(0x20200,52),(0x20300,64),(0x20400,88),(0x20500,96),(0x20600,108)) if version>=v)
            assert cl>=min_header and version<=0x20600,path
            if version>=0x20100:assert struct.unpack_from('>I',cd,44)[0]==0,('unsupported scattered CodeDirectory',path)
            if version>=0x20300 and not limit:limit=struct.unpack_from('>Q',cd,56)[0]
            algo,expected_size={1:('sha1',20),2:('sha256',32),3:('sha256',20),4:('sha384',48)}[htype]
            assert hsize==expected_size and 0<=psize<=31 and limit==off and limit>0,path
            pagesize=1<<psize if psize else limit
            assert ncode==(limit+pagesize-1)//pagesize and ncode>0,(path,limit,off,ncode)
            hash_start=hashoff-nspecial*hsize
            assert min_header<=identoff<hash_start<=hashoff<=cl and b'\x00' in cd[identoff:hash_start],path
            assert hashoff+ncode*hsize<=cl,path
            for page in range(ncode):
                actual=hashlib.new(algo,b[page*pagesize:min((page+1)*pagesize,limit)]).digest()[:hsize]
                stored=cd[hashoff+page*hsize:hashoff+(page+1)*hsize]
                assert actual==stored,('invalid code-page hash',path,page)
            dirs.append({'hash':algo,'page_hashes_verified':ncode,'code_limit':limit,
                         'flags':hex(flags),'adhoc':bool(flags&2),
                         'cdhash':hashlib.new(algo,cd).hexdigest()[:40]})
        assert 0 in types and dirs,('missing primary CodeDirectory',path)
        regions.sort(); assert all(a[1]<=b[0] for a,b in zip(regions,regions[1:])),path
        result.append({'cpu':hex(cpu),'subtype':hex(sub),'code_directories':dirs})
    return result

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--build-dir',type=pathlib.Path,default=pathlib.Path('build'))
    ap.add_argument('--baseline-dir',type=pathlib.Path);ap.add_argument('--version',default='5.09+mem5');a=ap.parse_args();build=a.build_dir.resolve()
    debs=sorted(build.glob('*.deb'));assert len(debs)==2,[p.name for p in debs]
    output=[]
    with tempfile.TemporaryDirectory(prefix='sbcpu-verify-') as tmp:
        for deb in debs:
            scheme=deb.stem.rsplit('-',1)[-1]; assert scheme in ('roothide','rootless'),deb.name
            meta=subprocess.check_output(['dpkg-deb','-f',str(deb)],text=True)
            fields=dict(line.split(': ',1) for line in meta.splitlines() if ': ' in line)
            assert fields['Package']=='com.sbcpu.floating' and fields['Version']==a.version,(deb.name,fields)
            expected='iphoneos-arm64e' if scheme=='roothide' else 'iphoneos-arm64'
            assert fields['Architecture']==expected,(deb.name,fields.get('Architecture'),expected)
            assert fields['Depends']=='mobilesubstrate, preferenceloader'
            stage=pathlib.Path(tmp)/scheme;stage.mkdir()
            subprocess.run(['dpkg-deb','-x',str(deb),str(stage)],check=True)
            files=[p for p in stage.rglob('*') if p.is_file()]
            assert not any(any(x in str(p.relative_to(stage)).lower() for x in ('hello','peach')) for p in files)
            prefix='var/jb/' if scheme=='rootless' else ''
            assert all(str(p.relative_to(stage)).startswith(prefix) for p in files)
            macho={}
            for path in files:
                if not path.is_symlink() and path.read_bytes()[:4] in MAGICS:
                    slices=verify_macho(path)
                    assert len(slices)==2 and {s['cpu'] for s in slices}=={'0x100000c'}
                    assert {s['subtype'] for s in slices}=={'0x0','0x80000002'}
                    macho[str(path.relative_to(stage))]=slices
            assert len(macho)==10 and any('SBCPUPrefs.bundle/SBCPUPrefs' in x for x in macho)
            filters={}
            for path in files:
                if path.suffix=='.plist' and path.parent.name=='DynamicLibraries':
                    filters[str(path.relative_to(stage))]=plistlib.loads(path.read_bytes())
            assert len(filters)==5,(scheme,list(filters))
            assert filters[prefix+'Library/MobileSubstrate/DynamicLibraries/SBCPUFloating.plist']['Filter']['Bundles']==['com.apple.springboard','com.apple.Preferences','com.apple.settings.BatteryUsageUI']
            licenses=[p for p in files if p.name=='LICENSE.TrollSpeed']; assert len(licenses)==1
            assert licenses[0].read_bytes()==(pathlib.Path(__file__).resolve().parents[1]/'LICENSE.TrollSpeed').read_bytes()
            resource_count=None
            if a.baseline_dir:
                old,=a.baseline_dir.glob(f'*fdc9a1c2083d-{scheme}.deb')
                prior=pathlib.Path(tmp)/('mem4-'+scheme)
                subprocess.run(['dpkg-deb','-x',str(old),str(prior)],check=True)
                paths=lambda d:{str(p.relative_to(d)):p for p in d.rglob('*') if p.is_file() or p.is_symlink()}
                before,after=paths(prior),paths(stage)
                assert before.keys()==after.keys(),(scheme,before.keys()^after.keys())
                assert {k for k,p in before.items() if not p.is_symlink() and p.read_bytes()[:4] in MAGICS}==macho.keys(),scheme
                for k in before.keys()-macho.keys():
                    assert before[k].is_symlink()==after[k].is_symlink(),k
                    if before[k].is_symlink():assert before[k].readlink()==after[k].readlink(),k
                    assert before[k].read_bytes()==after[k].read_bytes(),('mem4 resource differs',k)
                resource_count=len(before)-len(macho)
            report={'file':deb.name,'scheme':scheme,'size':deb.stat().st_size,
                    'sha256':hashlib.sha256(deb.read_bytes()).hexdigest(),'metadata':fields,
                    'mach_o_count':len(macho),'mach_o_slices':macho,
                    'code_directory_page_hashes':'all verified','injection_filters':filters,'trollspeed_mit_license_verified':True,
                    'mem4_payload_paths_equal':a.baseline_dir is not None,'mem4_non_macho_resources_byte_equal_count':resource_count}
            output.append(report)
    assert {p['scheme'] for p in output}=={'rootless','roothide'}
    (build/'VERIFICATION.json').write_text(json.dumps({'version':a.version,'packages':output,
      'device_installed':False,'simulator_does_not_validate_gpu_backdrop':True},ensure_ascii=False,indent=2)+'\n')
    (build/'SHA256SUMS').write_text(''.join(x['sha256']+'  '+x['file']+'\n' for x in output))
    for p in output:print(p['scheme'],p['metadata']['Architecture'],p['sha256'],p['mach_o_count'],'Mach-O; all slices/CodeDirectory code-page hashes PASS')
if __name__=='__main__':main()
