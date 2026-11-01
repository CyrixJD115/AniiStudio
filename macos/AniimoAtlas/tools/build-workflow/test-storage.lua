local factory=dofile('tools/build-workflow/storage.lua')
local function fixture()
 local space={demoMode=false,homeLandOwnerPlayerId=1,ornament={[10]={areaId=1},[11]={areaId=1},[20]={areaId=1}},itemMap={}}
 local me={id=1,space=space,itemCountBindMap={}};function me:getItemCountById()return 100 end;function me:checkHomelandRemoveOrnament(id)return space.ornament[id]~=nil end
 local rows={[10]={homeId=40100002,position={x=5.5,y=0,z=28.2},yawAngle=0,isTrash=false},[11]={homeId=40100002,position={x=6.5,y=0,z=28.2},yawAngle=0,isTrash=false},[20]={homeId=100,position={x=1,y=0,z=1},yawAngle=0,isTrash=false}}
 local calls=0;function space:removeOrnaments(ids)calls=calls+1;for _,id in ipairs(ids)do local home=rows[id].homeId;self.ornament[id]=nil;self.itemMap[home]=(self.itemMap[home]or 0)+1 end end
 local orig={_serializeFacility=function(id)return rows[id]end,_ensureOrnamentCallbackHooks=function()end,_getOrnamentResultRing=function()return {seq=1}end}
 local pg={me=me,space=space};local api=factory.new(pg,{['GameApp.CmdSocket.HomeCmdImplement']=orig})
 local p={operationUUID=string.rep('a',36),nonce=string.rep('b',64),items={{id=10,homeID=40100002,areaID=1,position=rows[10].position,yawAngle=0},{id=11,homeID=40100002,areaID=1,position=rows[11].position,yawAngle=0}}}
 return api,p,space,me,function()return calls end,pg,rows
end
local api,p,s,m,calls=fixture();assert(api.prepare(p).valid and calls()==0);assert(api.commit(p).dispatched and calls()==1);assert(api.commit(p).alreadyClaimed and calls()==1);assert(api.status(p).phase=='verified'and s.itemMap[40100002]==2 and s.ornament[20])
api,p,s,m,calls=fixture();p.items[2].id=10;assert(not api.prepare(p).valid and calls()==0)
api,p,s,m,calls=fixture();p.items[1].homeID=99;assert(not api.prepare(p).valid and calls()==0)
api,p,s,m,calls=fixture();assert(api.prepare(p).valid);s.itemMap[40100002]=1;assert(not api.commit(p).valid and calls()==0)
api,p,s,m,calls=fixture();assert(api.prepare(p).valid);s.ornament[30]={areaId=1};assert(not api.commit(p).valid and calls()==0)
api,p,s,m,calls=fixture();assert(api.prepare(p).valid);function m:getItemCountById()return 101 end;assert(not api.commit(p).valid and calls()==0)
local pg;api,p,s,m,calls,pg=fixture();assert(api.prepare(p).valid);pg.space={};assert(not api.commit(p).valid and calls()==0)
api,p,s,m,calls=fixture();assert(api.prepare(p).valid);function s:removeOrnaments(ids)for _,id in ipairs(ids)do self.ornament[id]=nil end end;assert(api.commit(p).dispatched);assert(api.status(p).phase=='submitted')
print('PASS storage: normal RPC, no MultiSelect, exact IDs, spare return, unchanged world/wallet, duplicates/stale/owner/stock rejected, missing inventory delta stays uncertain')
