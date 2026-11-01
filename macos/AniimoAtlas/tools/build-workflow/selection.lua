-- Exact-ID selection through the game's ordinary editor. Never moves or buys.
local M={}
function M.new(pg,loaded)
 local owner,space=pg.me,pg.space
 local original=assert(loaded['GameApp.CmdSocket.HomeCmdImplement'])
 local function own()assert(pg.me==owner and pg.space==space and owner.space==space and space.demoMode==false and space.homeLandOwnerPlayerId==owner.id,'owner_changed')end
 local function ctrl()
  own();local c=assert(pg.global and pg.global.ui and pg.global.ui.homelandMultiSelect,'open_multi_select')
  assert(c.view,'open_multi_select_panel');assert(c.editor,'editor_unavailable');assert(not c.carGroup,'vehicle_editor')
  return c
 end
 local function safe(fn)local ok,v=pcall(fn);return ok and v or {valid=false,reason=tostring(v)}end
 local api={}
 function api.state()return safe(function()local c=ctrl();local ids=c:getSelectedOrnamentIdList();return {valid=true,areaId=c.areaId or -1,selected=ids,maxCount=c:getMultiSelectMaxCount()}end)end
 function api.select(p)return safe(function()
  local c=ctrl();local area=p.areaId;assert(area==0 or area==1 or area==2,'area');assert(c.areaId==nil or c.areaId==area,'wrong_multi_select_area');local expected,entities,seen={}, {},{}
  assert(type(p.items)=='table' or type(p.items)=='userdata','items')
  for i=1,501 do
   local item=p.items[i];if item==nil then break end;assert(i<=500,'count_limit')
   local id=item.id;assert(type(id)=='number' and id>0 and id==math.floor(id) and not expected[id],'instance_id')
   local row=assert(original._serializeFacility(id));local ornament=assert(space.ornament[id]);assert(ornament.areaId==area and row.homeId==item.homeID and not row.isTrash,'instance_changed')
   -- Selection follows stable imported IDs even after the user moves the build.
   local ent=assert(c:getOrnamentEnt(id),'entity_not_loaded');assert(ent.ornamentId==id and ent.homeTemplateId==item.homeID and ent.areaId==area and ent:canEntEdit(),'entity_not_editable')
   entities[#entities+1]=ent;expected[id]=true
  end
  assert(#entities>0 and #entities<=c:getMultiSelectMaxCount(),'count_limit')
  for _,id in ipairs(c:getSelectedOrnamentIdList())do assert(expected[id],'unrelated_selection_preserved')end
  local grouped=c:collectOrnamentEditGroupEntities(entities)
  local pending={}
  for _,ent in ipairs(grouped)do assert(expected[ent.ornamentId] and not seen[ent.ornamentId],'unrelated_group');seen[ent.ornamentId]=true
   if not c.editor.multiSelectEntities[ent.id] then pending[#pending+1]=ent end
  end
  for id in pairs(expected)do assert(seen[id],'incomplete_group')end
  own();if #pending>0 then c.editor:addMultiSelectEntities(pending)end
  local selected=c:getSelectedOrnamentIdList();local actual={};assert(#selected==#entities,'incomplete_selection')
  for _,id in ipairs(selected)do assert(expected[id] and not actual[id],'selection_mismatch');actual[id]=true end
  return {valid=true,count=#selected,areaId=area,selected=selected,worldChanged=false}
 end)end
 return api
end
return M
