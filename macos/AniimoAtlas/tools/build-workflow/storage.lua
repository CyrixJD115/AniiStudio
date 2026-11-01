-- Store uses the same removeOrnaments RPC as HomeEntityEditor.withdrawMultiSelectEntities.
-- No selection, editor mode, recycling, wallet mutation, or implicit retry.
local M={}
function M.new(pg,loaded)
 local me,space=pg.me,pg.space
 local original=assert(loaded['GameApp.CmdSocket.HomeCmdImplement'])
 local operations={};local used={};local count=0
 local function own()assert(pg.me==me and pg.space==space and me.space==space and space.demoMode==false and space.homeLandOwnerPlayerId==me.id,'owner_changed')end
 local function integer(n)assert(type(n)=='number' and n==math.floor(n) and n>=0 and n<=9007199254740991,'integer');return n end
 local function stock(id)
  local pair=me.itemCountBindMap[id];local n=space.itemMap[id]or 0
  if pair then for _,k in ipairs({1,2})do n=n+(pair[k]and pair[k][2]or 0)end end
  return integer(n)
 end
 local function row(id)
  local o=assert(space.ornament[id],'missing_instance');local r=assert(original._serializeFacility(id))
  assert(not r.isTrash,'trash');return {id=id,homeID=r.homeId,areaID=o.areaId,position={x=r.position.x,y=r.position.y,z=r.position.z},yawAngle=r.yawAngle,isTrash=false}
 end
 local function same(a,b)return a.id==b.id and a.homeID==b.homeID and a.areaID==b.areaID and a.yawAngle==b.yawAngle and a.position.x==b.position.x and a.position.y==b.position.y and a.position.z==b.position.z end
 local function snapshot()
  own();local all={};local n=0
  for id in pairs(space.ornament)do n=n+1;assert(n<=50000,'world_limit');local r=original._serializeFacility(id);all[id]={id=id,homeID=r.homeId,areaID=space.ornament[id].areaId,position={x=r.position.x,y=r.position.y,z=r.position.z},yawAngle=r.yawAngle,isTrash=r.isTrash}end
  return all
 end
 local function wallets()local v={};for _,id in ipairs({1,2,1010,1011})do v[id]=integer(me:getItemCountById(id))end;return v end
 local function unchanged(a,b)return same(a,b)and a.isTrash==b.isTrash end
 local function validItems(p)
  own();assert(type(p.items)=='table' or type(p.items)=='userdata','items')
  local ids,expected,counts={}, {},{}
  for i=1,501 do
   local source=p.items[i];if source==nil then break end;assert(i<=500,'count_limit')
   local id=integer(source.id);assert(id>0 and not expected[id],'duplicate');local actual=row(id);assert(same(actual,source),'instance_changed')
   assert(type(me.checkHomelandRemoveOrnament)=='function' and me:checkHomelandRemoveOrnament(id),'normal_store_rejected')
   ids[#ids+1]=id;expected[id]=actual;counts[actual.homeID]=(counts[actual.homeID]or 0)+1
  end
  assert(#ids>0,'items');own();return ids,expected,counts
 end
 local function safe(f)local ok,v=pcall(f);return ok and v or {valid=false,reason=tostring(v)}end
 local api={}
 function api.capabilities()return safe(function()own();return {version=1,normalStore=true,requiresMultiSelect=false,snapshotVersion=1}end)end
 function api.getFacilities()return safe(function()
  own();local rows={};for id,o in pairs(space.ornament)do local r=assert(original._serializeFacility(id));r.areaId=o.areaId;rows[#rows+1]=r;assert(#rows<=50000,'world_limit')end
  own();return {facilities=rows,total=#rows}
 end)end
 function api.prepare(p)return safe(function()
  assert(type(p.operationUUID)=='string'and #p.operationUUID==36 and operations[p.operationUUID]==nil,'operation')
  assert(type(p.nonce)=='string'and #p.nonce==64 and not used[p.nonce]and count<128,'nonce')
  local ids,expected,counts=validItems(p);local stockBefore={};for id in pairs(counts)do stockBefore[id]=stock(id)end
  local frozen={};for _,id in ipairs(ids)do frozen[#frozen+1]=expected[id]end
  count=count+1;used[p.nonce]=true;operations[p.operationUUID]={items=frozen,ids=ids,expected=expected,counts=counts,stockBefore=stockBefore,before=snapshot(),wallet=wallets(),nonce=p.nonce,phase='prepared'}
  return {valid=true,operationUUID=p.operationUUID,nonce=p.nonce,count=#ids,phase='prepared'}
 end)end
 function api.commit(p)return safe(function()
  own();local op=assert(operations[p.operationUUID],'operation');assert(op.nonce==p.nonce,'nonce')
  if op.phase~='prepared'then return {valid=true,phase=op.phase,dispatched=false,alreadyClaimed=true}end
  validItems({items=op.items});local now=snapshot()
  for id,r in pairs(op.before)do assert(now[id]and unchanged(r,now[id]),'world_changed')end
  for id in pairs(now)do assert(op.before[id],'world_changed')end
  for id,n in pairs(op.stockBefore)do assert(stock(id)==n,'stock_changed')end
  local wallet=wallets();for id,n in pairs(op.wallet)do assert(wallet[id]==n,'wallet_changed')end
  original._ensureOrnamentCallbackHooks();op.since=original._getOrnamentResultRing().seq
  op.phase='submitted';own();space:removeOrnaments(op.ids)
  return {valid=true,phase=op.phase,dispatched=true,callbackSinceSeq=op.since,count=#op.ids}
 end)end
 function api.status(p)return safe(function()
  own();local op=assert(operations[p.operationUUID],'operation');local now=snapshot();local verified=op.phase=='submitted'or op.phase=='verified'
  for id,r in pairs(op.before)do
   if op.expected[id]then if now[id]then verified=false end
   elseif not now[id]or not unchanged(r,now[id])then verified=false end
  end
  for id in pairs(now)do if not op.before[id]then verified=false end end
  for id,n in pairs(op.stockBefore)do if stock(id)~=n+op.counts[id]then verified=false end end
  local wallet=wallets();for id,n in pairs(op.wallet)do if wallet[id]~=n then verified=false end end
  if verified then op.phase='verified'end
  local rows={};for id in pairs(op.counts)do rows[#rows+1]={homeID=id,before=op.stockBefore[id],after=stock(id),returned=op.counts[id]}end
  return {valid=true,phase=op.phase,operationUUID=p.operationUUID,count=#op.ids,inventory=rows,previousPlacementsUnchanged=verified,walletUnchanged=verified,callbackSinceSeq=op.since}
 end)end
 return api
end
return M
