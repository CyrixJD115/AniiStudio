"""Read-only export of installed Aniimo (Parmon) skinned meshes, skeleton and PBR textures to GLB.
Original geometry/textures only; Unity shader effects are not reproduced."""
import sys,os,hashlib,traceback,math
from common import *
from UnityPy.helpers.MeshHelper import MeshHandler
from PIL import Image
OUT=Path(os.environ.get('OUT','/private/tmp/claude-501/pets/out'));OUT.mkdir(exist_ok=True,parents=True)
def tex_image(reader,ref):
 t=ptr(reader,ref['m_Texture']) if ref and ref['m_Texture']['m_PathID'] else None
 return t.read().image.convert('RGBA') if t else None
def png(img,alpha=False):
 if max(img.size)>1024:img=img.resize((max(1,img.width*1024//max(img.size)),max(1,img.height*1024//max(img.size))),Image.LANCZOS)
 b=io.BytesIO()
 if alpha:img.save(b,format='PNG',optimize=True)
 else:img.convert('RGB').save(b,format='JPEG',quality=88)
 return b.getvalue(),('image/png' if alpha else 'image/jpeg')
def export(pid):
 ps=prefab_paths('P_Parmon_'+pid);assert len(ps)==1,('prefab',pid,len(ps))
 go=asset_object(ps[0]);bin=bytearray()
 doc={'asset':{'version':'2.0','generator':'AniimoAtlas installed Parmon exporter; original geometry/base textures'},'scene':0,'scenes':[{'nodes':[]}],'nodes':[],'meshes':[],'skins':[],'materials':[],'textures':[],'images':[],'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}],'bufferViews':[],'accessors':[],'buffers':[]}
 def add(raw,target=None):
  bin.extend(bytes(-len(bin)%4));v={'buffer':0,'byteOffset':len(bin),'byteLength':len(raw)}
  if target:v['target']=target
  doc['bufferViews'].append(v);bin.extend(raw);return len(doc['bufferViews'])-1
 def acc(raw,ctype,count,typ,target=None,minmax=None):
  a={'bufferView':add(raw,target),'componentType':ctype,'count':count,'type':typ}
  if minmax:a['min'],a['max']=minmax
  doc['accessors'].append(a);return len(doc['accessors'])-1
 def flt(rows,w,target=34962,mm=False):
  flat=[v for r in rows for v in r];return acc(struct.pack('<%df'%len(flat),*flat),5126,len(rows),'VEC%d'%w,target,([min(r[i] for r in rows) for i in range(w)],[max(r[i] for r in rows) for i in range(w)]) if mm else None)
 imgcache={}
 def image(key,img,alpha=False):
  if key in imgcache:return imgcache[key]
  raw,mime=png(img,alpha);doc['images'].append({'bufferView':add(raw),'mimeType':mime});doc['textures'].append({'source':len(doc['images'])-1,'sampler':0});imgcache[key]=len(doc['textures'])-1;return imgcache[key]
 matcache={}
 def material(reader):
  tree=reader.read_typetree()
  if tree['m_Name'] in matcache:return matcache[tree['m_Name']]
  sp=tree['m_SavedProperties'];cols=dict(sp.get('m_Colors',[]));tx=dict(sp.get('m_TexEnvs',[]))
  c=cols.get('_BaseColor',dict(r=1,g=1,b=1,a=1));d={'name':tree['m_Name'],'doubleSided':True,'pbrMetallicRoughness':{'baseColorFactor':[c[k] for k in 'rgba'],'metallicFactor':1,'roughnessFactor':1}}
  base=None
  for role in ('_BaseMap','_MainTex','_AlbedoMap'):
   base=tex_image(reader,tx.get(role)) if role in tx else None
   if base:d['pbrMetallicRoughness']['baseColorTexture']={'index':image(tree['m_Name']+role,base,any('ALPHATEST' in k or 'TRANSPARENT' in k for k in (tree.get('m_ValidKeywords',[]) or [])))};break
  n=tex_image(reader,tx.get('_NormalMap')) if '_NormalMap' in tx else None
  if n:d['normalTexture']={'index':image(tree['m_Name']+'n',n.convert('RGB'))}
  mo=tex_image(reader,tx.get('_MaskMap')) if '_MaskMap' in tx else None
  if mo:
   r,g,b,a=mo.split()  # MOHR: R metallic, G occlusion, B height, A roughness
   mr=Image.merge('RGB',(Image.new('L',mo.size,255),a,r));d['pbrMetallicRoughness']['metallicRoughnessTexture']={'index':image(tree['m_Name']+'mr',mr)}
   d['occlusionTexture']={'index':image(tree['m_Name']+'o',Image.merge('RGB',(g,g,g)))}
  else:d['pbrMetallicRoughness'].update(metallicFactor=0,roughnessFactor=.8)
  e=tex_image(reader,tx.get('_EmissiveMap')) if '_EmissiveMap' in tx else None
  if e:
   ec=cols.get('_EmissiveColor',dict(r=1,g=1,b=1));d['emissiveTexture']={'index':image(tree['m_Name']+'e',e.convert('RGB'))};peak=max(1.0,ec['r'],ec['g'],ec['b']);d['emissiveFactor']=[max(0,ec[k])/peak*(0.35 if peak>1 else 1.0) for k in 'rgb']
  kw=tree.get('m_ValidKeywords',[]) or []
  if any('ALPHATEST' in k for k in kw):d.update(alphaMode='MASK',alphaCutoff=.5)
  elif any('TRANSPARENT' in k for k in kw) and 'baseColorTexture' in d['pbrMetallicRoughness']:d.update(alphaMode='BLEND')
  doc['materials'].append(d);matcache[tree['m_Name']]=len(doc['materials'])-1;return matcache[tree['m_Name']]
 tid={}  # transform path_id -> node index
 pending=[]  # (node index, smr component, platform renderers)
 visited=set()
 def walk(r,depth=0):
  assert depth<40 and len(visited)<4096
  g=r.read_typetree();comps=[ptr(r,x['component']) for x in g['m_Component']]
  trans=next(c for c in comps if c.type.name=='Transform');t=trans.read_typetree();tr=t['m_LocalPosition'];q=t['m_LocalRotation'];sc=t['m_LocalScale']
  node={'name':g['m_Name'],'translation':[-tr['x'],tr['y'],tr['z']],'rotation':[q['x'],-q['y'],-q['z'],q['w']],'scale':[sc[k] for k in 'xyz'],'children':[]}
  doc['nodes'].append(node);ni=len(doc['nodes'])-1;tid[trans.path_id]=ni
  smr=next((c for c in comps if c.type.name=='SkinnedMeshRenderer'),None)
  if smr:
   for c in comps:
    if c.type.name!='MonoBehaviour':continue
    ref=c.read_typetree().get('m_PlatformData')
    if not ref or not ref.get('m_PathID'):continue
    pt=ptr(c,ref).read_typetree();lods=pt.get('m_DefaultConfig',{}).get('m_Lods',[])
    if pt.get('m_Enable',True) and lods and smr.read_typetree().get('m_Enabled',True):pending.append((ni,smr,lods[0]['m_Renderers']))
  for ref in t['m_Children']:
   ch=ptr(trans,ref)
   if ch is None:continue
   cg=ptr(ch,ch.read_typetree()['m_GameObject'])
   if cg is None:continue
   name=cg.read_typetree()['m_Name']
   if re.search(r'LOD[1-9]',name,re.I):continue
   node['children'].append(walk(cg,depth+1))
  return ni
 root=walk(go)
 S=[[-1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]
 def conv(m):  # row-major 4x4 Unity->glTF handedness: S*M*S
  return [[S[i][i]*m[i][j]*S[j][j] for j in range(4)] for i in range(4)]
 skins={};meshes=0
 for ni,smr,renderers in pending:
  st=smr.read_typetree();bones=[ptr(smr,b) for b in st['m_Bones']]
  for ri,rd in enumerate(renderers):
   mp=rd['m_MeshPath']['m_Path']
   if not mp:continue
   mo=asset_object(mp);mesh=mo.read();h=MeshHandler(mesh);h.process()
   assert len(mesh.m_BindPose)==len(bones),('skin mismatch',mp,len(mesh.m_BindPose),len(bones))
   pos=[[-v[0],v[1],v[2]] for v in h.m_Vertices];nor=[[-n[0],n[1],n[2]] for n in h.m_Normals];uv=[[u[0],1-u[1]] for u in h.m_UV0]
   tan=[[-t[0],t[1],t[2],-t[3]] for t in h.m_Tangents] if h.m_Tangents else None
   at={'POSITION':flt(pos,3,mm=True),'NORMAL':flt(nor,3),'TEXCOORD_0':flt(uv,2)}
   if tan:at['TANGENT']=flt(tan,4)
   if h.m_BoneWeights is None:ji=[[0,0,0,0]]*len(pos);wt=[[1.,0.,0.,0.]]*len(pos)
   else:ji=[(list(map(int,x[:4]))+[0]*4)[:4] for x in h.m_BoneIndices];wt=[(list(map(float,x[:4]))+[0.]*4)[:4] for x in h.m_BoneWeights]
   at['JOINTS_0']=acc(struct.pack('<%dH'%(4*len(ji)),*[v for r in ji for v in r]),5123,len(ji),'VEC4',34962)
   at['WEIGHTS_0']=flt(wt,4)
   mats=[asset_object(x['m_Path']) for x in rd['m_MaterialList']];tris=h.get_triangles();assert len(tris)<=len(mats)
   prims=[]
   for slot,tl in enumerate(tris):
    idx=[i for a,b,c in tl for i in (a,c,b)];assert idx and max(idx)<len(pos)
    prims.append({'attributes':at,'indices':acc(struct.pack('<%dI'%len(idx),*idx),5125,len(idx),'SCALAR',34963),'material':material(mats[slot])})
   doc['meshes'].append({'name':mesh.m_Name,'primitives':prims})
   key=tuple(b.path_id for b in bones)
   if key not in skins:
    ibm=[]
    for bp in mesh.m_BindPose:  # UnityPy Matrix4x4f e00..e33 row-major
     m=[[getattr(bp,'e%d%d'%(i,j)) for j in range(4)] for i in range(4)];c=conv(m);ibm+= [c[r][col] for col in range(4) for r in range(4)]  # column-major
    doc['skins'].append({'joints':[tid[b.path_id] for b in bones],'inverseBindMatrices':acc(struct.pack('<%df'%len(ibm),*ibm),5126,len(bones),'MAT4')});skins[key]=len(doc['skins'])-1
   child={'name':mesh.m_Name,'mesh':len(doc['meshes'])-1,'skin':skins[key]};doc['nodes'].append(child);doc['nodes'][ni]['children'].append(len(doc['nodes'])-1);meshes+=1
 assert meshes>0,'no skinned meshes'
 doc['scenes'][0]['nodes']=[root];bin.extend(bytes(-len(bin)%4));doc['buffers']=[{'byteLength':len(bin)}]
 text=json.dumps(doc,separators=(',',':')).encode();text+=b' '*(-len(text)%4)
 glb=struct.pack('<III',0x46546c67,2,28+len(text)+len(bin))+struct.pack('<II',len(text),0x4e4f534a)+text+struct.pack('<II',len(bin),0x004e4942)+bin
 f='Parmon_'+pid+'.glb';(OUT/f).write_bytes(glb)
 return {'file':f,'bytes':len(glb),'sha256':hashlib.sha256(glb).hexdigest(),'sourcePrefab':ps[0],'meshes':meshes,'joints':len(doc['nodes']),'materials':len(doc['materials'])}
if __name__=='__main__':
 for pid in sys.argv[1:]:
  try:print(pid,export(pid))
  except Exception:print(pid,'FAIL',traceback.format_exc(limit=5))
