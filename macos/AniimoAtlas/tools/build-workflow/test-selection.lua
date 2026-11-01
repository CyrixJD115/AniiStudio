local factory=dofile('tools/build-workflow/selection.lua')
local function fixture()
 local entities={};local selected={};local space={demoMode=false,homeLandOwnerPlayerId='owner',ornament={}}
 for i=1,408 do local id=10000+i;space.ornament[id]={areaId=1};entities[id]={id=id,ornamentId=id,homeTemplateId=100,areaId=1,canEntEdit=function()return true end}end
 local editor={multiSelectEntities={}};local calls=0
 function editor:addMultiSelectEntities(items)calls=calls+1;for _,e in ipairs(items)do selected[#selected+1]=e.ornamentId;self.multiSelectEntities[e.id]=e end end
 local ctrl={view={},editor=editor,areaId=1}
 function ctrl:getSelectedOrnamentIdList()return selected end
 function ctrl:getMultiSelectMaxCount()return 500 end
 function ctrl:getOrnamentEnt(id)return entities[id]end
 function ctrl:collectOrnamentEditGroupEntities(items)return items end
 local pg={me={id='owner',space=space},space=space,global={ui={homelandMultiSelect=ctrl}}}
 local source={_serializeFacility=function(id)return {homeId=100,isTrash=false,position={x=1,y=2,z=3}}end}
 local api=factory.new(pg,{['GameApp.CmdSocket.HomeCmdImplement']=source})
 local items={};for i=1,408 do items[i]={id=10000+i,homeID=100,position={x=1,y=2,z=3}}end
 return api,{areaId=1,items=items},selected,function()return calls end,ctrl
end
local api,p,selected,calls=fixture();assert(api.select(p).count==408 and calls()==1);assert(api.select(p).count==408 and calls()==1)
api,p,selected,calls=fixture();selected[1]=999;assert(not api.select(p).valid and calls()==0 and selected[1]==999)
api,p,selected,calls=fixture();p.items[2].id=p.items[1].id;assert(not api.select(p).valid and calls()==0)
api,p,selected,calls=fixture();p.items[2].homeID=101;assert(not api.select(p).valid and calls()==0)
api,p,selected,calls=fixture();p.items[2].position.x=2;assert(api.select(p).count==408 and calls()==1)
print('PASS selection MOCK: exact408, one normal editor call, idempotence, unrelated selection preserved, changed/duplicate IDs rejected; no game writes')
