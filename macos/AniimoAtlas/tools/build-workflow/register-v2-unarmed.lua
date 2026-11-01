-- REVIEW TEMPLATE ONLY. Do not execute in a game process without fresh session/code/owner guards.
assert(pg and pg.me and pg.space and pg.me.space==pg.space and pg.space.demoMode==false and pg.space.homeLandOwnerPlayerId==pg.me.id)
require('Data.revert_home_place_data')
local prefix,path='atlasBuildWorkflowV2','Atlas.Private.BuildWorkflowV2'
local system=assert(pg.game.cmdSocket)
assert(system.cmdPrefixes[prefix]==nil and package.loaded[path]==nil,'workflow_already_registered')
local function clock() return CS.UnityEngine.Time.realtimeSinceStartup end
local factory=(function()
-- V2: one ordinary shop currency per operation. Mixed/material redemption remains unsupported.
-- Offline authored adapter; registration never purchases.
local M={}
local function integer(n) assert(type(n)=='number' and n==n and n>=0 and n<=2147483647 and n==math.floor(n),'invalid_number');return n end
local function view(t) assert(type(t)=='table' or type(t)=='userdata','missing_map');return t end
local function count(t,id) local n=view(t)[id];return n==nil and 0 or integer(n) end
local function array(t,max) view(t);local out={};for i=1,max+1 do local v=t[i];if v==nil then return out end;assert(i<=max,'array_limit');out[i]=v end;error('array_limit') end
function M.new(pg,loaded,d)
 local ledger={};local issuedNonces={};local operationCount=0;local originalMe,originalSpace,originalOwner=pg.me,pg.space,pg.me.id
 local function own()
  assert(pg.me==originalMe and pg.space==originalSpace and pg.me.space==pg.space and pg.space.demoMode==false and pg.me.id==originalOwner and pg.space.homeLandOwnerPlayerId==originalOwner,'owner_changed')
  return pg.me,pg.space
 end
 local function config(n) return view(loaded[n]) end
 local function row(id) return view(config('Data.home_object_data')[id]) end
 local function bag(m,id)
  local constants,ic=config('Common.Const.Const'),config('Common.Const.ItemConst')
  local item=view(config('Data.item_data')[id]);assert(item.invId~=nil and item.invId~=ic.INV_TYPE_SPECIAL,'unsupported_inventory')
  assert(constants.INV_BOUND_TYPE_BOUND==1 and constants.INV_BOUND_TYPE_UNBOUND==2 and constants.ITEM_LOCKED_NOT==2,'inventory_constants')
  local pair=view(m.itemCountBindMap)[id];if pair==nil then return 0 end
  view(pair);local n=0;for _,bound in ipairs({1,2}) do if pair[bound]~=nil then n=n+count(pair[bound],2) end end;return integer(n)
 end
 local function snapshot(items,currency)
  local m,s=own();assert(m.getItemCountById==d.walletGetter,'wallet_binding')
  local result={wallet=integer(d.walletGetter(m,currency)),stock={}}
  for i,item in ipairs(items) do result.stock[i]=integer(bag(m,item.templateId)+count(s.itemMap,item.templateId)) end
  own();return result
 end
 local function same(a,b)
  if a.wallet~=b.wallet or #a.stock~=#b.stock then return false end
  for i,n in ipairs(a.stock) do if b.stock[i]~=n then return false end end;return true
 end
 local function eligible(m,id,currency)
  local r=row(id);local constants=config('Common.Const.Const')
  assert(r.buyMoneyType==currency and integer(r.buyMoneyNum)>0 and r.getWay==view(constants.HOMELAND_ORNAMENT_GET_WAY).BUY,'unsupported_offer')
  for _,v in ipairs({r,view(config('Data.item_data')[id])}) do
   if v.areaNo then local allowed=false;for _,region in ipairs(array(v.areaNo,64)) do if region==m.serverArea then allowed=true end end;assert(allowed,'region_locked') end
  end
  local release=config('Data.home_item_release_data')[id]
  if release then view(release);assert(not release.timeRefId and not release.commodityId and not release.lotteryId,'dynamic_offer') end
  local condition=r.unlockCondition
  if condition~=nil then
   integer(condition);local c=view(config('Data.custom_trigger_data')[condition]);assert(c.conditionUse==0 and c.userId==0,'dynamic_condition')
   assert(not m.isGuidancePlayer or c.virtualPlayerEnable==1,'guidance')
   local word=math.floor(condition/32)+1;local bit=condition%32
   local n=view(view(m.triggerMap).completeCustomSet)[word] or 0
   assert(type(n)=='number' and n==math.floor(n) and n>=-2147483648 and n<=4294967295,'condition_binding')
   assert(math.floor((n%4294967296)/(2^bit))%2==1,'item_locked')
  end
  local drawing=r.unlockByItemId or 0;integer(drawing)
  assert(drawing==0 or view(m.unlockedHomelandFurnitureMap)[id]==true,'drawing_locked')
  return r
 end
 local function capacity(items,missing,currency)
  local m,s=own();local level=integer(view(m.homeBasicInfo).level);assert(level<=200,'level_bound')
  local groups={}
  for i,item in ipairs(items) do
   local r=eligible(m,item.templateId,currency);local key=r.placeId or -item.templateId
   local g=groups[key]
   if not g then
    local base=0;local members
    if r.placeId then
     local levels=view(config('Data.home_object_place_data')[r.placeId])
     for lv=level,1,-1 do if levels[lv]~=nil then base=integer(view(levels[lv]).getWay or 0);break end end
     members=array(config('Data.revert_home_place_data')[r.placeId],256)
    else base=integer(r.maxNum or config('Common.Const.Const').HOMELAND_ORNAMENT_DEFAULT_MAX_PLACE_NUM);members={item.templateId} end
    local maximum=0
    for _,area in ipairs(array(r.homelandAreaIds or {0},64)) do
     local ar=config('Data.homeland_area_data')[area];local ratio=ar and view(ar).placeNumRatio or 1
     assert(type(ratio)=='number' and ratio>=0 and ratio<=1000,'area_ratio');maximum=maximum+math.ceil(base*ratio)
    end
    local used,seen=0,{}
    for _,id in ipairs(members) do
     integer(id);assert(id>0 and not seen[id] and row(id).placeId==r.placeId,'group_members');seen[id]=true
     used=used+count(m.statHomelandOrnament,id)+count(m.statHomeCarOrnament,id)+bag(m,id)+count(s.itemMap,id)
    end
    assert(seen[item.templateId],'missing_group_member');g={maximum=integer(maximum),used=integer(used),need=0,members=seen,areas=table.concat(array(r.homelandAreaIds or {0},64),',')};groups[key]=g
   end
   assert(g.members[item.templateId] and g.areas==table.concat(array(r.homelandAreaIds or {0},64),','),'group_binding');g.need=integer(g.need+missing[i]);assert(g.used+g.need<=g.maximum,'capacity_exceeded')
  end
 end
 local function descriptor(p)
  assert(type(p)=='table' and type(p.manifestSHA256)=='string' and #p.manifestSHA256==64 and not p.manifestSHA256:find('[^0-9a-f]'),'manifest')
  integer(p.buildId);assert(p.buildId>0,'build_id')
  local currency=integer(p.currencyId);assert(currency==1 or currency==2 or currency==1010 or currency==1011,'unsupported_currency')
  local items=array(p.items,256);assert(#items>0,'empty_items');local result,seen,total={},{},0
  for i,item in ipairs(items) do
   view(item);integer(item.templateId);integer(item.required);assert(item.templateId>0 and item.required>0 and not seen[item.templateId],'invalid_item');seen[item.templateId]=true
   total=integer(total+item.required);assert(total<=500,'piece_limit');result[i]={templateId=item.templateId,required=item.required}
  end
  return result,currency
 end
 local function quote(p)
  local items,currency=descriptor(p);local m=own();local snap=snapshot(items,currency);local rows,needs,total={},{},0
  for i,item in ipairs(items) do
   local r=eligible(m,item.templateId,currency);local missing=math.max(0,item.required-snap.stock[i]);needs[i]=missing
   local cost=integer(missing*r.buyMoneyNum);total=integer(total+cost)
   rows[i]={templateId=item.templateId,required=item.required,owned=snap.stock[i],missing=missing,unitPrice=r.buyMoneyNum,cost=cost,currencyId=currency}
  end
  capacity(items,needs,currency);assert(total<=snap.wallet,'insufficient_wallet')
  return {status='ready',buildId=p.buildId,manifestSHA256=p.manifestSHA256,currencyId=currency,totalCost=total,wallet=snap.wallet,items=rows},items,snap
 end
 local function safe(fn) local ok,value=pcall(fn);if ok then return value end;return {status='unavailable',reason=tostring(value)} end
 local function clock() local n=d.monotonicSeconds();assert(type(n)=='number' and n==n and n>=0,'clock');return n end
 local function validID(id) return type(id)=='string' and #id==36 and id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') end
 local function public(op)
  local legs={};for i,l in ipairs(op.legs) do legs[i]={templateId=l.templateId,quantity=l.quantity,cost=l.cost,state=l.state,callbackCode=l.code,before=l.before,after=l.after} end
  return {currencyId=op.currency,status=op.state,operationUUID=op.id,buildId=op.buildId,manifestSHA256=op.manifest,totalBudget=op.budget,legs=legs,serverExactlyOnce=false}
 end
 local function reconcile(op)
  if op.state~='pending' and op.state~='uncertain' then return end
  if op.state=='uncertain' then op.halted=true end
  if not op.legs[op.next] or op.legs[op.next].state~='submitted' then return end
  local l=op.legs[op.next];local current=snapshot(op.items,op.currency);l.after=current
  for i,n in ipairs(l.before.stock) do
   local delta=current.stock[i]-n;local wanted=i==l.index and l.quantity or 0
   if delta~=0 and delta~=wanted then op.state='uncertain';return end
   if i~=l.index and delta~=0 then op.state='uncertain';return end
  end
  local charged=l.before.wallet-current.wallet
  if charged~=0 and charged~=l.cost then op.state='uncertain';return end
  if l.code==0 and current.stock[l.index]-l.before.stock[l.index]==l.quantity and charged==l.cost then
   l.state='reconciled';op.next=op.next+1;op.state=op.next>#op.legs and 'complete' or (op.halted and 'uncertain' or 'ready')
  elseif clock()-l.started>=30 then op.state='uncertain' end
 end
 local api={}
 function api.quote(p) return safe(function() return quote(p) end) end
 function api.status(p) return safe(function() assert(validID(p.operationUUID),'operation_id');local op=assert(ledger[p.operationUUID],'unknown_operation');own();reconcile(op);return public(op) end) end
 function api.prepare(p) return safe(function()
  assert(d.enabled==true and type(p)=='table' and validID(p.operationUUID),'not_authorized')
  assert(type(p.nonce)=='string' and #p.nonce==64 and not p.nonce:find('[^0-9a-f]'),'nonce')
  local op=ledger[p.operationUUID]
  if not op then
   assert(operationCount<32,'operation_limit');local q,items,snap=quote(p);integer(p.maxSpend);assert(p.maxSpend==q.totalCost,'price_changed')
   local legs={};for i,item in ipairs(q.items) do if item.missing>0 then legs[#legs+1]={templateId=item.templateId,quantity=item.missing,cost=item.cost,index=i,state='new'} end end
   op={currency=p.currencyId,id=p.operationUUID,items=items,legs=legs,next=1,budget=q.totalCost,manifest=p.manifestSHA256,buildId=p.buildId,state=#legs==0 and 'complete' or 'ready'};ledger[op.id]=op;operationCount=operationCount+1
  end
  own();reconcile(op)
  assert(op.currency==p.currencyId and op.manifest==p.manifestSHA256 and op.buildId==p.buildId and op.budget==p.maxSpend,'operation_changed')
  if op.state~='ready' and op.state~='prepared' then return public(op) end
  local l=op.legs[op.next]
  if l.state=='new' then
   assert(not issuedNonces[p.nonce],'nonce_reused');issuedNonces[p.nonce]=true
   local snap=snapshot(op.items,op.currency)
   if op.next>1 then assert(same(snap,op.legs[op.next-1].after),'state_changed') end
   local needs={};for i=1,#op.items do needs[i]=0 end
   for i=op.next,#op.legs do needs[op.legs[i].index]=op.legs[i].quantity end;capacity(op.items,needs,op.currency)
   assert(snap.wallet>=l.cost,'insufficient_wallet');l.before=snap;l.nonce=p.nonce;l.preparedAt=clock();l.state='prepared';op.state='prepared'
  end
  return {currencyId=op.currency,status='prepared',operationUUID=op.id,buildId=op.buildId,manifestSHA256=op.manifest,totalBudget=op.budget,leg=op.next,templateId=l.templateId,quantity=l.quantity,cost=l.cost,nonce=l.nonce,before=l.before}
 end) end
 function api.commit(p) return safe(function()
  assert(d.enabled==true and validID(p.operationUUID),'not_authorized');local op=assert(ledger[p.operationUUID],'unknown_operation');own();reconcile(op)
  integer(p.leg);assert(p.leg>=1 and p.leg<=#op.legs,'leg');local l=op.legs[p.leg]
  if l.state~='prepared' then return public(op) end
  assert(op.next==p.leg and op.state=='prepared' and p.nonce==l.nonce,'reservation_changed')
  if clock()-l.preparedAt>=30 then l.nonce=nil;op.state='uncertain';return public(op) end
  local snap=snapshot(op.items,op.currency);assert(same(snap,l.before),'state_changed');local m=own();eligible(m,l.templateId,op.currency)
  assert(m.serverMsg==d.serverMsg,'dispatch_binding')
  -- Burn before invoking the ordinary validated shop RPC. Never resend this leg.
  l.nonce=nil;l.state='submitted';l.started=clock();op.state='pending'
  local ok=pcall(d.serverMsg,m,'RPC_CS_BuyMultiOrnament',l.templateId,l.quantity,function(code)
   if l.code~=nil or l.state~='submitted' or (op.state~='pending' and op.state~='uncertain') then return end
   if type(code)~='number' or code~=math.floor(code) then op.state='uncertain';return end
   l.code=code;if code~=0 then l.state='rejected';op.state='rejected' end
  end)
  if not ok then op.state='uncertain' end
  return public(op)
 end) end
 return api
end
return M

end)()
local purchaseEnabled=false -- Deliberately unarmed. Fresh live review/verification is still required.
local api=factory.new(pg,package.loaded,{enabled=purchaseEnabled,walletGetter=pg.me.getItemCountById,serverMsg=pg.me.serverMsg,monotonicSeconds=clock})
local module={}
for _,name in ipairs({'quote','prepare','commit','status'}) do
 local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end
end
module.capabilities=function()return {ok=true,data={version=2,purchaseEnabled=purchaseEnabled,currencies={1,2,1010,1011},maxPieces=500,areas={0},uprightUnitScaleOnly=true}}end
package.loaded[path]=module
system:registerPrefix(prefix,path,{requireAuth=true})
assert(system.cmdPrefixes[prefix].requireAuth==true)
