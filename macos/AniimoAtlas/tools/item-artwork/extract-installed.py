"""Offline extraction of exact item-data artwork references from the selected install."""
from pathlib import Path
import json,re,struct,hashlib,UnityPy,sys
root=Path(sys.argv[1]);references=json.loads(Path(sys.argv[2]).read_text());out=Path(sys.argv[3]);out.mkdir(parents=True,exist_ok=True)
def name(value):return Path(value.lstrip('$').replace('\\','/')).stem.lower()
wanted={name(v) for v in references.values()};manifest=root/'PackageManifest_DefaultPackage_3746914.bytes';data=manifest.read_bytes();pos=48;count=struct.unpack_from('<I',data,44)[0]
def scalar(fmt):
 global pos
 v=struct.unpack_from(fmt,data,pos)[0];pos+=struct.calcsize(fmt);return v
def string():
 global pos
 n=scalar('<H');v=data[pos:pos+n].decode();pos+=n;return v
assets={}
for _ in range(count):
 path=string();bundle=scalar('<i');deps=[scalar('<i') for _ in range(scalar('<H'))];flags=scalar('<I');n=name(path)
 if n in wanted:assets.setdefault(n,set()).add(bundle)
bundle_count=scalar('<i');bundle_start=pos;bundles=[]
for match in re.finditer(rb'[A-Za-z0-9_]+\.uab',data[bundle_start:]):
 start=bundle_start+match.start();end=bundle_start+match.end()
 for skip in range(3):
  at=start+skip;raw=data[at:end]
  if data[at-1]==len(raw):bundles.append(raw[:-4].decode()+'_'+data[end:end+16].hex()+'.uab');break
assert len(bundles)==bundle_count
resolved={n:next(iter(ids)) for n,ids in assets.items() if len(ids)==1};needed=sorted(set(resolved.values()));images={};provenance={};failures={}
print('Item references',len(references),'unique assets',len(wanted),'bundles',len(needed),flush=True)
for index,bundle_id in enumerate(needed):
 path=root/bundles[bundle_id];env=UnityPy.load(str(path));targets={n for n,b in resolved.items() if b==bundle_id};matches={}
 for obj in env.objects:
  if obj.type.name not in ['Sprite','Texture2D']:continue
  obj_data=obj.read();n=name(obj_data.m_Name)
  if n not in targets:continue
  if n in matches and obj.type.name!='Sprite':continue
  matches[n]=(obj,obj_data)
 for n,(obj,obj_data) in matches.items():
  try:
   image=obj_data.image
   # Preserve original pixels/alpha; no generated or recolored substitute artwork.
   import io
   blob=io.BytesIO();image.save(blob,format='PNG');raw=blob.getvalue();digest=hashlib.sha256(raw).hexdigest();file='item-'+digest[:20]+'.png';target=out/file
   if not target.exists():target.write_bytes(raw)
   images[n]=file;provenance[n]={'bundle':path.name,'pathID':obj.path_id,'kind':obj.type.name,'imageSHA256':digest}
  except Exception as error:failures[n]=type(error).__name__
 print('Bundle',index+1,'of',len(needed),'artwork',len(images),flush=True)
byID={id:images[name(icon)] for id,icon in references.items() if name(icon) in images}
result={'version':1,'manifestSHA256':hashlib.sha256(data).hexdigest(),'byItemID':byID,'byAssetName':images,'missingItemIDs':sorted(set(references)-set(byID),key=int),'failures':failures,'provenance':provenance}
(out/'item-artwork.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print('ARTWORK COVERAGE',len(byID),'of',len(references),'items; missing',len(result['missingItemIDs']),flush=True)
