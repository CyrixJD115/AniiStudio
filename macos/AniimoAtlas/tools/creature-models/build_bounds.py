import json,struct
from pathlib import Path
import numpy as np
root=Path('/Users/kevinhowe/Documents/ChatGPT/AniiStudio macOS App/work/aniistudio-review-20261024/macos/AniimoAtlas')
src=root/'Sources/AniimoAtlas/Resources/CreatureModels'
installed=Path('/Users/kevinhowe/Applications/AniimoAtlas.app/Contents/Resources/AniimoAtlas_AniimoAtlas.bundle/Contents/Resources')
report={};fail={}
for path in sorted(src.glob('Parmon_*.glb')):
 p=installed/path.name if (installed/path.name).exists() else path
 try:
  raw=p.read_bytes();length,kind=struct.unpack_from('<II',raw,12);doc=json.loads(raw[20:20+length]);bstart=20+length+8;binary=memoryview(raw)[bstart:]
  def acc(i):
   a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']];size=np.dtype(dtype).itemsize
   x=np.ndarray((a['count'],n),dtype=dtype,buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',n*size),size))
   if a.get('normalized') and a['componentType']!=5126:x=x.astype(float)/np.iinfo(dtype).max
   return x
  nodes=doc['nodes'];parents={c:i for i,n in enumerate(nodes) for c in n.get('children',[])};cache={}
  def world(i):
   if i in cache:return cache[i]
   n=nodes[i]
   if 'matrix' in n:m=np.array(n['matrix']).reshape(4,4).T
   else:
    x,y,z,w=n.get('rotation',[0,0,0,1]);m=np.eye(4);m[:3,:3]=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]];m[:3,:3]=m[:3,:3]@np.diag(n.get('scale',[1,1,1]));m[:3,3]=n.get('translation',[0,0,0])
   cache[i]=world(parents[i])@m if i in parents else m;return cache[i]
  lows=[];highs=[]
  for i,n in enumerate(nodes):
   if 'mesh' not in n:continue
   for primitive in doc['meshes'][n['mesh']]['primitives']:
    a=primitive['attributes'];pos=acc(a['POSITION']);v=np.column_stack((pos,np.ones(len(pos))))
    if 'skin' in n and 'WEIGHTS_0' in a:
     s=doc['skins'][n['skin']];ib=acc(s['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);mat=np.array([world(j)@ib[k] for k,j in enumerate(s['joints'])]);j=acc(a['JOINTS_0']).astype(int);w=acc(a['WEIGHTS_0']);out=np.einsum('nkij,nj,nk->ni',mat[j],v,w)
    else:out=v@world(i).T
    assert np.isfinite(out).all();lows.append(out[:,:3].min(axis=0));highs.append(out[:,:3].max(axis=0))
  low=np.min(lows,axis=0);high=np.max(highs,axis=0);assert np.linalg.norm(high-low)>1e-5
  report[path.name]={'min':low.tolist(),'max':high.tolist()}
 except Exception as e:fail[path.name]=str(e)
print('bounds',len(report),'failures',fail)
(root/'Sources/AniimoAtlas/Resources/creature-stage-bounds.json').write_text(json.dumps(report,separators=(',',':')))
(root/'work/roster-models/bounds-failures.json').write_text(json.dumps(fail))
for name in ['Parmon_10693.glb','Parmon_1059403.glb','Parmon_1003305.glb']:print(name,report.get(name))
