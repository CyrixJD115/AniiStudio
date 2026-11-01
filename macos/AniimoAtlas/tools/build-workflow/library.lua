-- Normal game combo-library queries. No purchase, placement, or deletion.
local M={}
function M.new(pg,loaded)
 local owner=pg.me
 local utils=assert((loaded['Common.Homeland.HomeBlueprintUtils'] or require('Common.Homeland.HomeBlueprintUtils')))
 local constants=assert((loaded['Common.Const.HomeBlueprintConst'] or require('Common.Const.HomeBlueprintConst')))
 local pending=false;local updatedAt=nil;local errorCode=nil;local operations={};local operationCount=0
 local function clock()return CS.UnityEngine.Time.realtimeSinceStartup end
 local function own()assert(pg.me==owner and pg.space and owner.space==pg.space and pg.space.demoMode==false and pg.space.homeLandOwnerPlayerId==owner.id,'owner_changed')end
 local function safe(fn)local ok,v=pcall(fn);return ok and v or {valid=false,reason=tostring(v)}end
 local function list(kind)
  local result={};local rows=owner:getHomeBlueprintCachedList(kind)
  for _,row in ipairs(rows)do
   assert(#result<100,'library_limit')
   result[#result+1]={id=tostring(row._id or row.blueprintId or ''),code=row.code or row.sourceCode or (kind==constants.SOURCE_TYPE.UPLOADED and row._id) or '',name=row.name or row.title or '',sourceType=kind,pieceCount=type(row.ornaments)=='table' and #row.ornaments or 0}
  end
  return result
 end
 local api={}
 function api.zoneContext()return safe(function()
  own();local rows={};local home=pg.game.home;local utils=assert(loaded['Common.Utils.HomeLandUtils'])
  for id,zone in pairs(utils.getHomelandZoneUnlockData())do
   assert(#rows<256,'zone_limit')
   rows[#rows+1]={id=id,areaID=zone.areaId or 0,x=zone.prefabPos[1],z=zone.prefabPos[2],width=home.zoneWidth,depth=home.zoneHeight,unlocked=pg.space.unlockZone[id]==true}
  end
  return {valid=true,zones=rows}
 end)end
 function api.state()return safe(function()
  own();local uploaded=assert(constants.SOURCE_TYPE.UPLOADED);local saved=assert(constants.SOURCE_TYPE.SAVED_OTHER)
  return {valid=true,version=2,pending=pending,updatedAt=updatedAt,errorCode=errorCode,
   ownLimit=utils.getUploadBlueprintLimit(owner),savedLimit=utils.getSavedOtherBlueprintLimit(owner),
   own=list(uploaded),saved=list(saved),sourceTypes={uploaded=uploaded,saved=saved},
   maxPieces=utils.getConfig('maxFurniturePerBlueprint')}
 end)end
 function api.refresh()return safe(function()
  own();assert(not pending,'refresh_pending');pending=true;errorCode=nil
  local left=2
  local function done(code)if pg.me~=owner then return end;if code~=nil and code~=0 then errorCode=code end;left=left-1;if left==0 then pending=false;updatedAt=CS.UnityEngine.Time.realtimeSinceStartup end end
  owner:getHomeBlueprintTabList(constants.SOURCE_TYPE.UPLOADED,0,50,done)
  owner:getHomeBlueprintTabList(constants.SOURCE_TYPE.SAVED_OTHER,0,50,done)
  return {valid=true,pending=pending}
 end)end
 local function snapshot(kind)local out={};for _,r in ipairs(owner:getHomeBlueprintCachedList(kind))do out[tostring(r._id or r.blueprintId or '')]=true end;return out end
 local function placed(p)
  local ids,entities,seen={}, {},{}
  local command=assert(loaded['GameApp.CmdSocket.HomeCmdImplement'])
  for i=1,501 do local item=p.items and p.items[i];if item==nil then break end;assert(i<=500,'piece_limit')
   local id=item.id;assert(type(id)=='number' and id==math.floor(id) and id>0 and not seen[id],'instance_id');seen[id]=true
   local row=assert(command._serializeFacility(id));assert(row.homeId==item.homeID and not row.isTrash,'instance_changed')
   assert(pg.space.ornament[id].areaId==p.areaId,'wrong_area')
   local ent=assert(pg.game.home:getHomeEntity(id),'entity_not_loaded');assert(ent.homeTemplateId==item.homeID,'entity_changed');ids[#ids+1]=id;entities[#entities+1]=ent
  end
  assert(#ids>=2 and #ids<=utils.getConfig('maxFurniturePerBlueprint'),'piece_limit')
  local x1,x2,z1,z2,y1,y2=pg.game.home.editor:calcEntitiesBounds(entities)
  assert(x1 and x2 and z1 and z2 and y1 and y2,'bounds_unavailable')
  return ids,{math.ceil(x2-x1),math.ceil(y2-y1),math.ceil(z2-z1)}
 end
 function api.prepare(p)return safe(function()
  own();assert(not pending and updatedAt and clock()-updatedAt<=60,'refresh_library')
  assert(type(p.operationUUID)=='string' and #p.operationUUID==36 and operations[p.operationUUID]==nil and operationCount<32,'operation')
  assert(type(p.nonce)=='string' and #p.nonce==36,'nonce')
  local mode=p.mode;assert(mode=='placed' or mode=='shared','mode')
  local kind=mode=='placed' and constants.SOURCE_TYPE.UPLOADED or constants.SOURCE_TYPE.SAVED_OTHER
  local limit=mode=='placed' and utils.getUploadBlueprintLimit(owner) or utils.getSavedOtherBlueprintLimit(owner)
  local before=snapshot(kind);local count=0;for _ in pairs(before)do count=count+1 end;assert(count<limit,'combo_slots_full')
  local ids,range
  if mode=='placed' then
   assert(type(p.name)=='string' and #p.name>0 and #p.name<=utils.getConfig('maxBlueprintNameLength') and not p.name:find('[%c]'),'name')
   assert(p.shareable==true,'shareable_confirmation_required')
   ids,range=placed(p)
  else assert(type(p.code)=='string' and #p.code==8 and p.code:match('^[A-Z0-9]+$'),'code')end
  operationCount=operationCount+1
  operations[p.operationUUID]={phase='ready',nonce=p.nonce,created=clock(),mode=mode,kind=kind,before=before,count=count,limit=limit,ids=ids,range=range,name=p.name,code=p.code,source=p}
  return {valid=true,phase='ready',operationUUID=p.operationUUID,mode=mode,count=count,limit=limit,pieceCount=ids and #ids or nil,shareable=mode=='placed'}
 end)end
 function api.status(p)return safe(function()
  own();local op=assert(operations[p.operationUUID],'operation_unavailable')
  if op.phase=='accepted' then
   local added={};for _,row in ipairs(owner:getHomeBlueprintCachedList(op.kind))do local id=tostring(row._id or row.blueprintId or '');if not op.before[id]then added[#added+1]=row end end
   if #added==1 and (op.mode=='shared' or (added[1].name or added[1].title)==op.name)then
    local row=added[1];op.phase='complete';op.result={id=tostring(row._id or row.blueprintId),code=row.code or row.sourceCode or (op.mode=='placed' and row._id) or op.code,name=row.name or row.title or op.name,pieceCount=type(row.ornaments)=='table' and #row.ornaments or nil}
   end
  end
  return {valid=true,operationUUID=p.operationUUID,phase=op.phase,code=op.resultCode,result=op.result}
 end)end
 function api.commit(p)return safe(function()
  own();local op=assert(operations[p.operationUUID],'operation_unavailable');assert(op.phase=='ready' and op.nonce==p.nonce and clock()-op.created<=60,'not_ready')
  local current=snapshot(op.kind);local count=0;for id in pairs(current)do assert(op.before[id],'library_changed');count=count+1 end;assert(count==op.count and count<op.limit,'library_changed')
  if op.mode=='placed' then local ids,range=placed(op.source);assert(#ids==#op.ids,'instance_changed');for i,id in ipairs(ids)do assert(id==op.ids[i],'instance_changed')end;op.range=range end
  op.phase='pending';op.nonce=nil
  local function done(code)if pg.me~=owner then return end;op.resultCode=code;op.phase=code==0 and 'accepted' or 'rejected'end
  if op.mode=='placed' then owner:uploadHomeBlueprint(op.ids,op.name,'Created with Aniimo Atlas',{},op.range,done)
  else owner:saveOtherHomeBlueprint(op.code,done)end
  return api.status({operationUUID=p.operationUUID})
 end)end
 return api
end
return M
