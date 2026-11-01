import json,struct,re,glob,io
from pathlib import Path
from functools import lru_cache
import UnityPy
W=Path('/Users/kevinhowe/Documents/ChatGPT/AniiStudio macOS App')
root=Path('/Volumes/Extreme SSD/GameHub/steamapps/common/Aniimo/Aniimo_Data/StreamingAssets/cvs/res/uab/win/DefaultPackage')
lookup={x['name'].lower():b['bundle'] for b in json.loads((W/'Research/2026-10-28/patch-update/new-bundle-directory-index.json').read_text())['bundles'] for x in b['files']}
data=next(root.glob('PackageManifest_DefaultPackage_*.bytes')).read_bytes();pos=48;count=struct.unpack_from('<I',data,44)[0]
def num(fmt):
 global pos
 v=struct.unpack_from(fmt,data,pos)[0];pos+=struct.calcsize(fmt);return v
def string():
 global pos
 n=num('<H');s=data[pos:pos+n].decode();pos+=n;return s
assets={}
for _ in range(count):
 path=string();bid=num('<i');deps=[num('<i') for _ in range(num('<H'))];flags=num('<I');assets[path.lower()]=bid
bundle_count=num('<i');bundles=[]
for m in re.finditer(rb'[A-Za-z0-9_]+\.uab',data[pos:]):
 start=pos+m.start();end=pos+m.end()
 for skip in range(3):
  at=start+skip;raw=data[at:end]
  if data[at-1]==len(raw):bundles.append(raw[:-4].decode()+'_'+data[end:end+16].hex()+'.uab');break
assert len(bundles)==bundle_count
@lru_cache(maxsize=8)
def load(b):return UnityPy.load(str(root/b))
def obj(cab,pid):
 env=load(lookup[cab.lower()]);return next(o for o in env.objects if o.path_id==pid and o.assets_file.name.lower()==cab.lower())
def ptr(source,ref):
 if not ref.get('m_PathID'):return None
 if ref['m_FileID']==0:return source.assets_file.objects[ref['m_PathID']]
 cab=source.assets_file.externals[ref['m_FileID']-1].path.split('/')[-1] if ref['m_FileID'] else source.assets_file.name
 return obj(cab,ref['m_PathID'])
@lru_cache(maxsize=4096)
def asset_object(path):
 path=path.lower();bid=assets.get(path)
 if bid is None:raise ValueError('absent: '+path)
 env=load(bundles[bid]);matches=[]
 for ab in env.objects:
  if ab.type.name!='AssetBundle':continue
  for k,v in ab.read_typetree()['m_Container']:
   if k.lower()==path:matches.append(ptr(ab,v['asset']))
 if len(matches)!=1:raise ValueError('ambiguous: '+path)
 return matches[0]
def prefab_paths(name):return [k for k in assets if k.endswith('/'+name.lower()+'.prefab')]
