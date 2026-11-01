-- Area-aware normal placement checks. No permission to buy or move existing pieces.
local M={}
function M.new(pg,loaded,d)
 local original=assert(loaded['GameApp.CmdSocket.HomeCmdImplement'])
 local area=d.areaID or 1;assert(area==1 or area==2,'area');local owner,space,home=pg.me,pg.space,pg.game.home
 local function own()
  assert(pg.me==owner and pg.space==space and owner.space==space and space.demoMode==false and space.homeLandOwnerPlayerId==owner.id and pg.game.home==home,'owner_changed')
 end
 own()
 -- Give the existing validator a private area context. Never change the shared
 -- Production validator, its constants, or its callbacks.
 local isolated,functions={},{}
 for k,v in pairs(original) do
  isolated[k]=v
  if type(v)=='function' then
   local ok,bytes=pcall(string.dump,v)
   if ok then functions[v]=assert(loadstring(bytes)) end
  end
 end
 -- Native HomeCmd helpers read the area from pg.game.home, not just M.
 -- Bind only these private clones to an area view; native methods keep their
 -- original receiver and all normal bounds/collision checks remain enabled.
 local areaHome;areaHome=setmetatable({LOCK_ZONE_AREA_ID=area},{__index=function(_,key)
  local value=home[key]
  if key=='checkBoundsLock' then return function(receiver,requestedArea,worldPosition,worldRotation,bounds)
   assert(receiver==areaHome and requestedArea==area,'bounds_area')
   return home:checkBoundsLock(area,home:getLocalPosition(area,worldPosition),home:getLocalRotation(area,worldRotation),bounds)
  end end
  if type(value)=='function' then return function(receiver,...)
   assert(receiver==areaHome or receiver==home,'home_receiver')
   return value(home,...)
  end end
  return value
 end})
 local areaGame=setmetatable({home=areaHome},{__index=pg.game})
 local areaPG=setmetatable({game=areaGame},{__index=pg})
 for source,copy in pairs(functions) do
  setfenv(copy,setmetatable({pg=areaPG},{__index=getfenv(source)}))
  for index=1,255 do
   local name,value=debug.getupvalue(source,index);if not name then break end
   if name=='_ENV' then -- Lua 5.2+ test hosts retain the private environment.
   elseif value==original or (type(value)=='table' and value._validatePlacement==original._validatePlacement) or functions[value] then
    assert(debug.setupvalue(copy,index,type(value)=='table' and isolated or functions[value]))
   else
    assert(type(debug.upvaluejoin)=='function','shared_context_unavailable')
    debug.upvaluejoin(copy,index,source,index)
   end
  end
 end
 for k,v in pairs(original) do isolated[k]=functions[v] or v end
 isolated._nextVirtualPlacementId=original._nextVirtualPlacementId
 isolated.LOCK_ZONE_AREA_ID=area
 -- Bounds API consumes area-local coordinates (the editor uses local entities).
 -- HomeCmd's nested closure otherwise retains its original area environment.
 isolated._checkPlacementBoundsLocked=function(template,position,rotation,scale)
  local world=Vector3(position[1],position[2],position[3])
  local bounds=original._getPlacementBoundSize(template,scale)
  return home:checkBoundsLock(area,home:getLocalPosition(area,world),home:getLocalRotation(area,rotation),bounds)
 end
 assert(isolated._validatePlacement~=original._validatePlacement and type(isolated._validatePlacement)=='function' and type(isolated._findCollidePreparedPlacement)=='function','validator_unavailable')
 local function number(n)assert(type(n)=='number' and n==n and math.abs(n)<=10000,'invalid_coordinate');return n end
 local function rotationDistance(a,b)
  local dot=a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w
  local aa=a.x*a.x+a.y*a.y+a.z*a.z+a.w*a.w
  local bb=b.x*b.x+b.y*b.y+b.z*b.z+b.w*b.w
  assert(aa>0.9999 and aa<1.0001 and bb>0.9999 and bb<1.0001,'quaternion_norm')
  return 2*math.acos(math.min(1,math.abs(dot)/math.sqrt(aa*bb)))*180/math.pi
 end
 local function close(a,b)return math.abs(number(a)-number(b))<0.00001 end
 local function array(t,max)
  assert(type(t)=='table' or type(t)=='userdata','invalid_array');local out={};for i=1,max+1 do if t[i]==nil then return out end;assert(i<=max,'array_limit');out[i]=t[i] end;error('array_limit')
 end
 local function inspect(p,geometryOnly)
  own();assert(p.areaId==area,'wrong_area')
  local items=array(p.items,500);assert(#items>0,'empty_batch')
  local totals={};local objects=assert(loaded['Data.home_object_data'])
  for _,item in ipairs(items) do
   local id=item.homeTemplateId;assert(type(id)=='number' and id>0 and id==math.floor(id),'template')
   local cfg=assert(objects[id]);assert(cfg.canHomePlace==true or cfg.canHomePlace==1,'not_placeable')
   local allowed=false;for _,a in ipairs(array(cfg.homelandAreaIds,8))do if a==area then allowed=true end end;assert(allowed,'area_not_allowed')
   totals[id]=(totals[id]or 0)+1
  end
  local prepared,dispatch={},{};local offsets={};local sharedArea=original.LOCK_ZONE_AREA_ID
  for i,item in ipairs(items) do
   local pos=assert(item.position);local scale=assert(item.scale)
   assert(scale.x==1 and scale.y==1 and scale.z==1,'unit_scale_only')
   local localPosition=Vector3(number(pos.x),number(pos.y),number(pos.z))
   for _,n in ipairs({pos.x,pos.y,pos.z})do assert(math.abs(n*100-math.floor(n*100+0.5))<0.0001,'centimetre_grid')end
   local worldPosition=home:getWorldPosition(area,localPosition)
   local back=home:getLocalPosition(area,worldPosition)
   assert(close(back.x,pos.x) and close(back.y,pos.y) and close(back.z,pos.z),'area_transform_changed')
   local localRotation
   if item.rotationCentidegrees~=nil then
    assert(d.fullTransforms==true,'full_transform_adapter_required')
    local r=array(item.rotationCentidegrees,3);assert(#r==3,'rotation_size')
    for _,v in ipairs(r)do assert(type(v)=='number' and v==math.floor(v) and v>=0 and v<36000,'rotation_grid')end
    localRotation=assert(Quaternion.Euler(r[1]/100,r[2]/100,r[3]/100))
    local utils=assert(loaded['Common.Utils.HomeLandUtils'])
    local rx,ry,rz=utils.buildOrnamentRotationFields(localRotation)
    -- The shipped codec may choose another Euler triple; prove the encoded
    -- rotation represents exactly the requested rigid orientation instead.
    local encoded=Quaternion.Euler(rx/100,ry/100,rz/100)
    assert(rotationDistance(localRotation,encoded)<=0.010001,'rotation_codec_loss')
   else localRotation=assert(original._makeYawQuaternion(number(item.yawAngle))) end
   local worldRotation=home:getWorldRotation(area,localRotation)
   if not d.fullTransforms then assert(math.abs(worldRotation.eulerAngles.x)<0.0001 and math.abs(worldRotation.eulerAngles.z)<0.0001,'upright_area_only') end
   local yaw=worldRotation.eulerAngles.y
   local id=item.homeTemplateId
   local params={homeTemplateId=id,position={x=worldPosition.x,y=worldPosition.y,z=worldPosition.z},scale={x=1,y=1,z=1}}
   if not d.fullTransforms then params.yawAngle=yaw end
   local valid,value=isolated._validatePlacement(params,{defaultRotation=worldRotation,skipInventory=geometryOnly==true,inventoryNeed=totals[id],countOffset=offsets[id]or 0})
   assert(original.LOCK_ZONE_AREA_ID==sharedArea,'shared_validator_changed')
   if valid and d.fullTransforms then assert(value and value.rotation and rotationDistance(value.rotation,worldRotation)<=0.0001,'validator_rotation_loss') end
   if not valid then return nil,{valid=false,reason=value and value.reason or 'Placement rejected',reasonCode=value and value.reasonCode or 'placement_rejected',item=i} end
   local collided=isolated._findCollidePreparedPlacement(value,prepared)
   if collided then return nil,{valid=false,reason='Pieces overlap within this batch',reasonCode='batch_collision',item=i} end
   prepared[#prepared+1]=value;offsets[id]=(offsets[id]or 0)+1
   dispatch[i]={homeTemplateId=id,areaId=area,position=Vector3(pos.x,pos.y,pos.z),rotation=localRotation,scale=Vector3(1,1,1)}
  end
  own();return dispatch
 end
 local function safe(fn)local ok,value=pcall(fn);if ok then return value end;return {valid=false,status='unavailable',reason=tostring(value)}end
 local api={}
 function api.inspectRotations(p)return safe(function()
  own();assert(d.fullTransforms==true,'full_transform_adapter_required');local result={}
  local utils=assert(loaded['Common.Utils.HomeLandUtils'])
  for _,item in ipairs(array(p.items,500))do
   local r=array(item.rotationCentidegrees,3);assert(#r==3,'rotation_size')
   for _,v in ipairs(r)do assert(type(v)=='number' and v==math.floor(v) and v>=0 and v<36000,'rotation_grid')end
   local q=Quaternion.Euler(r[1]/100,r[2]/100,r[3]/100)
   local x,y,z=utils.buildOrnamentRotationFields(q)
   local angle=rotationDistance(q,Quaternion.Euler(x/100,y/100,z/100))
   result[#result+1]={requested=r,rotationCentidegrees={x,y,z},angle=angle,valid=angle<=0.010001}
  end
  local valid=true;for _,row in ipairs(result)do valid=valid and row.valid end
  own();return {valid=valid,count=#result,items=result,readOnly=true}
 end)end
 -- Preview geometry only: the normal validator deliberately supports this
 -- read-only mode. Commit always re-runs inspect WITHOUT it, including inventory.
 function api.checkGeometry(p)return safe(function()
  assert(d.fullTransforms==true,'full_transform_adapter_required')
  local items,failure=inspect(p,true)
  return failure or {valid=true,geometryOnly=true,inventoryVerified=false,readOnly=true,areaId=area,count=#items}
 end)end
 function api.checkBatch(p)return safe(function()local items,failure=inspect(p);return failure or {valid=true,areaId=area,count=#items}end)end
 function api.getFacilities(p)return safe(function()
  own();local rows={};local seen={}
  for id,ornament in pairs(space.ornament)do
   assert(type(id)=='number' and id>0 and id<=9007199254740991 and id==math.floor(id) and not seen[id],'instance_id');seen[id]=true
   local row=assert(original._serializeFacility(id));row.areaId=assert(ornament.areaId);if d.fullTransforms then row.ornamentRecord=assert(space.ornamentBinaryData[id],'record_unavailable') end;assert(row.areaId==0 or row.areaId==1 or row.areaId==2,'instance_area');rows[#rows+1]=row;assert(#rows<=50000,'snapshot_limit')
  end
  own();return {facilities=rows,total=#rows}
 end)end
 function api.placeOrnamentBatch(p)return safe(function()
  assert(d.enabled==true,'not_enabled');local items,failure=inspect(p);if not items then return failure end
  own();assert(not original._isAddOrnamentLocked(),'placement_pending')
  original._ensureOrnamentCallbackHooks();local since=assert(original._getOrnamentResultRing().seq)
  -- Same normal client API used by the game's residential editor.
  space:addOrnaments(items)
  return {async=true,dispatched=true,callbackSinceSeq=since,areaId=area,count=#items}
 end)end
 return api
end
return M
