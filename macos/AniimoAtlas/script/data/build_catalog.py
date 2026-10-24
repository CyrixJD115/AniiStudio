"""Normalize the public Aniidex snapshot downloaded during research.
Inputs contain public catalog data only; JavaScript is parsed as literals, never executed.
"""
import json,re,pathlib,datetime,os
root=pathlib.Path(__file__).resolve().parents[2]
inputs=pathlib.Path(os.environ.get('ATLAS_CATALOG_INPUTS','/tmp'))
d=json.load(open(inputs/'atlas-data.json')); variants=json.load(open(inputs/'atlas-Mn.json')); images=json.load(open(inputs/'atlas-images.json')); videos=json.load(open(inputs/'atlas-Tr.json'))
old=json.load(open(root/'Sources/AniimoAtlas/Resources/creatures.json'))
official={r['name']:r['entryId'] for r in old}
elements={2:'Ice',3:'Water',4:'Lightning',5:'Fire',6:'Grass',8:'Earth',9:'Wind',12:'Dark',13:'Light'}
roman=['I','II','III','IV','V','VI','VII','VIII','IX','X']
def clean(s):return re.sub(r'<[^>]*>','',str(s)).replace('&nbsp;',' ')
def skills(rows):return [{'id':str(x.get('skillId',x.get('abilityId',i))), 'name':x.get('name',''), 'description':clean(x.get('description','')), 'kind':x.get('skillType','Mobility'), 'power':x.get('power',0), 'cost':x.get('epCost',0), 'cooldown':x.get('cd',0)} for i,x in enumerate(rows)]
rows=[]
for key,p in d['pets'].items():
 forms=[]
 for f in p.get('forms',[]):
  fid=str(f['variantId']);v=p if fid==key else variants.get(fid,{})
  appearance=[]
  for aid,img in images.get(fid,{}).items():
   title='Standard' if aid=='common' else 'Umbral' if aid=='umbral' else 'Dazzling Sparkling' if aid=='sparkling-11' else 'Shadow Sparkling' if aid=='sparkling-12' else 'Sparkling '+roman[int(aid[-2:])-1]
   appearance.append({'id':aid,'name':title,'imageURL':'https://aniidex.com'+img,'videoURL':('https://aniidex.com'+videos[fid][aid]) if aid in videos.get(fid,{}) else None})
  forms.append({'id':fid,'name':f['name'],'elements':[elements.get(x,'Unknown') for x in f['elementType']], 'artURL':'https://aniidex.com/images/aniimo/UI_PetHead_'+f['iconName']+'.webp','appearances':appearance, 'stats':v.get('baseStats',{}),'skills':skills(v.get('skills',[])), 'traits':[{'name':t['name'],'description':clean(t['description'])} for t in v.get('traits',[])], 'mobility':skills(v.get('mobilitySkills',[]))})
 if not forms:continue
 rows.append({'id':key,'entryId':official.get(p['name'],str(p.get('index',0)).zfill(3)), 'name':p['name'],'description':clean(p.get('description','')), 'stage':p.get('stageLabel','Unknown'),'role':p.get('function',''), 'family':p.get('family',''), 'availability':p.get('availability','unknown'), 'forms':forms, 'evolution':[{'id':str(e['petId']),'name':e['name'],'stage':e.get('stageLabel','')} for e in p.get('evolution',[])], 'evolutionConditions':[{'name':e.get('targetName','Evolution'),'description':' · '.join([clean(x.get('value','')) for x in e.get('levelConditions',[])]+[clean(e.get('questCondition',{}).get('description',''))]+[str(x.get('count',1))+' × '+x.get('itemName','Item') for x in e.get('itemConditions',[])])} for e in p.get('evolutionConditions',[])], 'sourceURL':'https://aniidex.com/aniimo/'+re.sub(r'[^a-z0-9]+','-',p['name'].lower()).strip('-')+'/'})
rows.sort(key=lambda p:(int(p['entryId']),p['name']))
out=root/'Sources/AniimoAtlas/Resources/catalog.json';out.write_text(json.dumps(rows,ensure_ascii=False,indent=2))
print('Species',len(rows),'forms',sum(len(p['forms']) for p in rows),'appearances',sum(len(f['appearances']) for p in rows for f in p['forms']))
print('Without rendered appearances',[(p['name'],f['name']) for p in rows for f in p['forms'] if not f['appearances']])
