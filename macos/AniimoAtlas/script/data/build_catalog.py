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
# Retain installed-patch form/style IDs when the public guide lags the client.
# Publicly refreshed details win where present; missing forms/styles survive.
supplement = root/'Sources/AniimoAtlas/Resources/patch-catalog-supplement.json'
if supplement.exists():
 by_id={c['id']:c for c in rows}
 for cached in json.loads(supplement.read_text()):
  current=by_id.get(cached['id'])
  if current is None:
   rows.append(cached);by_id[cached['id']]=cached;continue
  forms_by_id={f['id']:f for f in current['forms']}
  for form in cached['forms']:
   public=forms_by_id.get(form['id'])
   if public is None:current['forms'].append(form);continue
   appearances={a['id']:a for a in public['appearances']}
   public['appearances'] += [a for a in form['appearances'] if a['id'] not in appearances]
 rows.sort(key=lambda c:(int(c['entryId']),c['name']))
assert len(rows)>=100 and sum(len(p['forms']) for p in rows)>=200, 'Parsed catalog is empty or incomplete; existing catalog preserved'
out=root/'Sources/AniimoAtlas/Resources/catalog.json';out.write_text(json.dumps(rows,ensure_ascii=False,indent=2))
print('Species',len(rows),'forms',sum(len(p['forms']) for p in rows),'appearances',sum(len(f['appearances']) for p in rows for f in p['forms']))
print('Without rendered appearances',[(p['name'],f['name']) for p in rows for f in p['forms'] if not f['appearances']])

# Installed client numbering takes precedence over incomplete public guide IDs.
numbers_file = root/'Sources/AniimoAtlas/Resources/installed-aniilog-numbers.json'
if numbers_file.exists():
 numbers = json.loads(numbers_file.read_text())
 for row in rows:
  key = row['id'] if row['id'] in numbers else next((f['id'] for f in row['forms'] if f['id'] in numbers), None)
  if key: row['entryId'] = str(numbers[key]).zfill(3)
 rows.sort(key=lambda c:(int(c['entryId']),c['name']))
 (root/'Sources/AniimoAtlas/Resources/catalog.json').write_text(json.dumps(rows,ensure_ascii=False,separators=(',',':')))
# Keep shipped numeric stats/elements coherent when the public guide lags.
details_file = root/'Sources/AniimoAtlas/Resources/installed-form-details.json'
if details_file.exists():
 details = json.loads(details_file.read_text())['forms']
 for creature in rows:
  for form in creature['forms']:
   if form['id'] in details: form.update(details[form['id']])
 out.write_text(json.dumps(rows,ensure_ascii=False,separators=(',',':')))

regions_file = root/'Sources/AniimoAtlas/Resources/installed-catalog-regions.json'
if regions_file.exists():
 regions = json.loads(regions_file.read_text())
 for creature in rows:
  if creature['id'] in regions: creature['regionNames'] = regions[creature['id']]
 out.write_text(json.dumps(rows,ensure_ascii=False,separators=(',',':')))
# Explicit client avatar table fills styles missing from the public guide.
slots_file = root/'Sources/AniimoAtlas/Resources/installed-appearance-slots.json'
if slots_file.exists():
 slot_data = json.loads(slots_file.read_text())
 romans = ['I','II','III','IV','V','VI','VII','VIII','IX','X']
 for creature in rows:
  for form in creature['forms']:
   fid = form['id']
   if fid not in slot_data['forms']: continue
   if fid in slot_data['newAniimoIDs']:
    form['appearances'] = [a for a in form['appearances'] if a['id'] != 'umbral' or a.get('imageURL') or a.get('videoURL')]
   existing = {a['id'] for a in form['appearances']}
   for sid in slot_data['forms'][fid]:
    if sid in existing: continue
    name = 'Standard' if sid == 'common' else 'Dazzling Sparkling' if sid == 'sparkling-11' else 'Shadow Sparkling' if sid == 'sparkling-12' else 'Sparkling '+romans[int(sid.split('-')[1])-1]
    form['appearances'].append({'id':sid,'name':name,'imageURL':'atlas-pet://'+fid if sid == 'common' else '', 'videoURL':None})
 out.write_text(json.dumps(rows,ensure_ascii=False,separators=(',',':')))
# Resolve initial skills using the shipped baseFormPet relationship.
abilities_file = root/'Sources/AniimoAtlas/Resources/installed-ability-data.json'
if abilities_file.exists():
 ability_forms = json.loads(abilities_file.read_text())['forms']
 for creature in rows:
  for form in creature['forms']:
   if form['id'] in ability_forms:
    form['skills'] = ability_forms[form['id']]['skills']
    form['traits'] = ability_forms[form['id']]['traits']
    form['abilitiesFromInstalledClient'] = True
 out.write_text(json.dumps(rows,ensure_ascii=False,separators=(',',':')))
stages_file = root/'Sources/AniimoAtlas/Resources/installed-creature-stages.json'
if stages_file.exists():
 stages = json.loads(stages_file.read_text())['stages']
 for creature in rows:
  if creature['id'] in stages: creature['stage'] = stages[creature['id']]
  if creature['id'] in details: creature['description'] = details[creature['id']].get('description',creature['description'])
 out.write_text(json.dumps(rows,ensure_ascii=False,separators=(',',':')))
evolution_file = root/'Sources/AniimoAtlas/Resources/installed-evolution-data.json'
if evolution_file.exists():
 evolution = json.loads(evolution_file.read_text())
 families = evolution['families']
 for creature in rows:
  if creature['id'] in families: creature['evolution'] = families[creature['id']]
  if creature['id'] in evolution['baseConditions']: creature['evolutionConditions'] = evolution['baseConditions'][creature['id']]
 out.write_text(json.dumps(rows,ensure_ascii=False,separators=(',',':')))
