assert(pg and pg.me and pg.space and pg.me.space==pg.space and pg.space.demoMode==false and pg.space.homeLandOwnerPlayerId==pg.me.id)
require('Data.revert_home_place_data')
local system=assert(pg.game.cmdSocket)
local function clock() local n=CS.UnityEngine.Time.realtimeSinceStartup;assert(type(n)=='number' and n==n and n>=0);return n end
local function install(prefix,path,factory,version)
 if system.cmdPrefixes[prefix]~=nil then assert(system.cmdPrefixes[prefix].requireAuth==true and package.loaded[path]~=nil);return end
 assert(package.loaded[path]==nil)
 local api=factory.new(pg,package.loaded,{enabled=true,walletGetter=pg.me.getItemCountById,serverMsg=pg.me.serverMsg,monotonicSeconds=clock})
 local module={atlasRevision='atlas-purchase-vector-20261025'}
 for _,name in ipairs({'quote','prepare','commit','status'}) do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 module.capabilities=function()return {ok=true,data={version=version,purchaseEnabled=true,purchaseCurrency=1011,currencies={1,2,1010,1011},vectorCosts=version==3,maxPieces=500}}end
 package.loaded[path]=module;system:registerPrefix(prefix,path,{requireAuth=true});assert(system.cmdPrefixes[prefix].requireAuth==true)
end
install('atlasBuildWorkflowV1','Atlas.Private.BuildWorkflowV1',(function()
-- Supported ordinary Bud Ticket furniture. Registration never purchases.
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
 local function snapshot(items)
  local m,s=own();assert(m.getItemCountById==d.walletGetter,'wallet_binding')
  local result={wallet=integer(d.walletGetter(m,1011)),stock={}}
  for i,item in ipairs(items) do result.stock[i]=integer(bag(m,item.templateId)+count(s.itemMap,item.templateId)) end
  own();return result
 end
 local function same(a,b)
  if a.wallet~=b.wallet or #a.stock~=#b.stock then return false end
  for i,n in ipairs(a.stock) do if b.stock[i]~=n then return false end end;return true
 end
 local function eligible(m,id)
  local r=row(id);local constants=config('Common.Const.Const')
  assert(r.buyMoneyType==1011 and integer(r.buyMoneyNum)>0 and r.getWay==view(constants.HOMELAND_ORNAMENT_GET_WAY).BUY,'unsupported_offer')
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
 local function capacity(items,missing)
  local m,s=own();local level=integer(view(m.homeBasicInfo).level);assert(level<=200,'level_bound')
  local groups={}
  for i,item in ipairs(items) do
   local r=eligible(m,item.templateId);local key=r.placeId or -item.templateId
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
  local items=array(p.items,256);assert(#items>0,'empty_items');local result,seen,total={},{},0
  for i,item in ipairs(items) do
   view(item);integer(item.templateId);integer(item.required);assert(item.templateId>0 and item.required>0 and not seen[item.templateId],'invalid_item');seen[item.templateId]=true
   total=integer(total+item.required);assert(total<=500,'piece_limit');result[i]={templateId=item.templateId,required=item.required}
  end
  return result
 end
 local function quote(p)
  local items=descriptor(p);local m=own();local snap=snapshot(items);local rows,needs,total={},{},0
  for i,item in ipairs(items) do
   local r=eligible(m,item.templateId);local missing=math.max(0,item.required-snap.stock[i]);needs[i]=missing
   local cost=integer(missing*r.buyMoneyNum);total=integer(total+cost)
   rows[i]={templateId=item.templateId,required=item.required,owned=snap.stock[i],missing=missing,unitPrice=r.buyMoneyNum,cost=cost,currencyId=1011}
  end
  capacity(items,needs);assert(total<=snap.wallet,'insufficient_wallet')
  return {status='ready',buildId=p.buildId,manifestSHA256=p.manifestSHA256,currencyId=1011,totalCost=total,wallet=snap.wallet,items=rows},items,snap
 end
 local function safe(fn) local ok,value=pcall(fn);if ok then return value end;return {status='unavailable',reason=tostring(value)} end
 local function clock() local n=d.monotonicSeconds();assert(type(n)=='number' and n==n and n>=0,'clock');return n end
 local function validID(id) return type(id)=='string' and #id==36 and id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') end
 local function public(op)
  local legs={};for i,l in ipairs(op.legs) do legs[i]={templateId=l.templateId,quantity=l.quantity,cost=l.cost,state=l.state,callbackCode=l.code,before=l.before,after=l.after} end
  return {status=op.state,operationUUID=op.id,buildId=op.buildId,manifestSHA256=op.manifest,totalBudget=op.budget,legs=legs,serverExactlyOnce=false}
 end
 local function reconcile(op)
  if op.state~='pending' then return end
  local l=op.legs[op.next];local current=snapshot(op.items);l.after=current
  for i,n in ipairs(l.before.stock) do
   local delta=current.stock[i]-n;local wanted=i==l.index and l.quantity or 0
   if delta~=0 and delta~=wanted then op.state='uncertain';return end
   if i~=l.index and delta~=0 then op.state='uncertain';return end
  end
  local charged=l.before.wallet-current.wallet
  if charged~=0 and charged~=l.cost then op.state='uncertain';return end
  if l.code==0 and current.stock[l.index]-l.before.stock[l.index]==l.quantity and charged==l.cost then
   l.state='reconciled';op.next=op.next+1;op.state=op.next>#op.legs and 'complete' or 'ready'
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
   op={id=p.operationUUID,items=items,legs=legs,next=1,budget=q.totalCost,manifest=p.manifestSHA256,buildId=p.buildId,state=#legs==0 and 'complete' or 'ready'};ledger[op.id]=op;operationCount=operationCount+1
  end
  own();reconcile(op)
  assert(op.manifest==p.manifestSHA256 and op.buildId==p.buildId and op.budget==p.maxSpend,'operation_changed')
  if op.state~='ready' and op.state~='prepared' then return public(op) end
  local l=op.legs[op.next]
  if l.state=='new' then
   assert(not issuedNonces[p.nonce],'nonce_reused');issuedNonces[p.nonce]=true
   local snap=snapshot(op.items)
   if op.next>1 then assert(same(snap,op.legs[op.next-1].after),'state_changed') end
   local needs={};for i=1,#op.items do needs[i]=0 end
   for i=op.next,#op.legs do needs[op.legs[i].index]=op.legs[i].quantity end;capacity(op.items,needs)
   assert(snap.wallet>=l.cost,'insufficient_wallet');l.before=snap;l.nonce=p.nonce;l.preparedAt=clock();l.state='prepared';op.state='prepared'
  end
  return {status='prepared',operationUUID=op.id,buildId=op.buildId,manifestSHA256=op.manifest,totalBudget=op.budget,leg=op.next,templateId=l.templateId,quantity=l.quantity,cost=l.cost,nonce=l.nonce,before=l.before}
 end) end
 function api.commit(p) return safe(function()
  assert(d.enabled==true and validID(p.operationUUID),'not_authorized');local op=assert(ledger[p.operationUUID],'unknown_operation');own();reconcile(op)
  integer(p.leg);assert(p.leg>=1 and p.leg<=#op.legs,'leg');local l=op.legs[p.leg]
  if l.state~='prepared' then return public(op) end
  assert(op.next==p.leg and op.state=='prepared' and p.nonce==l.nonce,'reservation_changed')
  if clock()-l.preparedAt>=30 then l.nonce=nil;op.state='uncertain';return public(op) end
  local snap=snapshot(op.items);assert(same(snap,l.before),'state_changed');local m=own();eligible(m,l.templateId)
  assert(m.serverMsg==d.serverMsg,'dispatch_binding')
  -- Burn before invoking the ordinary validated shop RPC. Never resend this leg.
  l.nonce=nil;l.state='submitted';l.started=clock();op.state='pending'
  local ok=pcall(d.serverMsg,m,'RPC_CS_BuyMultiOrnament',l.templateId,l.quantity,function(code)
   if l.code~=nil or l.state~='submitted' or op.state~='pending' then return end
   if type(code)~='number' or code~=math.floor(code) then op.state='uncertain';return end
   l.code=code;if code~=0 then l.state='rejected';op.state='rejected' end
  end)
  if not ok then op.state='uncertain' end
  return public(op)
 end) end
 return api
end
return M

end)(),1)
install('atlasBuildWorkflowV2','Atlas.Private.BuildWorkflowV2',(function()
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

end)(),2)
install('atlasBuildWorkflowV3r3','Atlas.Private.BuildWorkflowV3r3',(function()
-- V3: ordinary shop and material-redemption costs, reconciled per resource.
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
 local function resource(m,s,id)
  local ordinary=id==1 or id==2 or id==1010 or id==1011
  return integer(d.walletGetter(m,id)+(ordinary and 0 or count(s.itemMap,id)))
 end
 local function snapshot(items,currency)
  local m,s=own();assert(m.getItemCountById==d.walletGetter,'wallet_binding')
  local result={wallet=0,stock={},balances={}}
  local ids={}
  for _,item in ipairs(items) do
   local r=row(item.templateId)
   if r.buyMoneyType and r.buyMoneyNum and r.buyMoneyNum>0 then ids[r.buyMoneyType]=true end
   for slot=1,2 do local id=r['buyItemId'..slot];if id then ids[id]=true end end
  end
  for id in pairs(ids) do integer(id);assert(id>0,'resource');for _,item in ipairs(items) do assert(id~=item.templateId,'resource_output_overlap') end
   result.balances[#result.balances+1]={itemID=id,amount=resource(m,s,id)}
  end
  table.sort(result.balances,function(a,b)return a.itemID<b.itemID end)
  for _,v in ipairs(result.balances) do result.wallet=integer(result.wallet+v.amount) end
  for i,item in ipairs(items) do result.stock[i]=integer(bag(m,item.templateId)+count(s.itemMap,item.templateId)) end
  own();return result
 end
 local function same(a,b)
  if a.wallet~=b.wallet or #a.stock~=#b.stock or #a.balances~=#b.balances then return false end
  for i,n in ipairs(a.stock) do if b.stock[i]~=n then return false end end
  for i,v in ipairs(a.balances) do if b.balances[i].itemID~=v.itemID or b.balances[i].amount~=v.amount then return false end end
  return true
 end
 local function costs(r)
  local c=config('Common.Const.Const');local ways=view(c.HOMELAND_ORNAMENT_GET_WAY);local out={};local seen={}
  if r.getWay==ways.BUY then
   local id=integer(r.buyMoneyType);assert(id>0,'unsupported_currency')
   if id~=1 and id~=2 and id~=1010 and id~=1011 then
    local item=view(config('Data.item_data')[id]);assert(item.invId~=nil and item.invId~=config('Common.Const.ItemConst').INV_TYPE_SPECIAL,'unsupported_currency_inventory')
   end
   assert(not r.buyItemId1 and not r.buyItemId2,'ambiguous_offer')
   out[1]={itemID=integer(r.buyMoneyType),amount=integer(r.buyMoneyNum)}
  else
   assert(r.getWay==ways.REDEEM and not r.buyMoneyType and not r.buyMoneyNum,'unsupported_offer')
   for slot=1,2 do local id,n=r['buyItemId'..slot],r['buyItemNum'..slot]
    if id or n then integer(id);integer(n);assert(id>0 and n>0 and not seen[id],'invalid_material_cost');seen[id]=true;out[#out+1]={itemID=id,amount=n} end
   end
  end
  assert(#out>0,'empty_cost');for _,v in ipairs(out) do assert(v.amount>0,'invalid_price') end
  table.sort(out,function(a,b)return a.itemID<b.itemID end);return out
 end
 local function scaled(unit,n)
  local out={};for i,v in ipairs(unit) do out[i]={itemID=v.itemID,amount=integer(v.amount*n)} end;return out
 end
 local function sum(values) local n=0;for _,v in ipairs(values) do n=integer(n+v.amount) end;return n end
 local function equalCosts(a,b)
  if type(a)~='table' or #a~=#b then return false end
  for i,v in ipairs(b) do if a[i].itemID~=v.itemID or a[i].amount~=v.amount then return false end end;return true
 end
 local function eligible(m,id,currency)
  local r=row(id);local constants=config('Common.Const.Const')
  costs(r)
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
  local currency=integer(p.currencyId);assert(currency==0,'unsupported_currency')
  local items=array(p.items,256);assert(#items>0,'empty_items');local result,seen,total={},{},0
  for i,item in ipairs(items) do
   view(item);integer(item.templateId);integer(item.required);assert(item.templateId>0 and item.required>0 and not seen[item.templateId],'invalid_item');seen[item.templateId]=true
   total=integer(total+item.required);assert(total<=500,'piece_limit');result[i]={templateId=item.templateId,required=item.required}
  end
  return result,currency
 end
 local function quote(p)
  local items,currency=descriptor(p);local m=own();local snap=snapshot(items,currency);local rows,needs,total,totals={},{},0,{}
  for i,item in ipairs(items) do
   local r=eligible(m,item.templateId,currency);local missing=math.max(0,item.required-snap.stock[i]);needs[i]=missing
   local unit=costs(r);local costVector=scaled(unit,missing);local cost=sum(costVector);total=integer(total+cost)
   for _,v in ipairs(costVector) do totals[v.itemID]=integer((totals[v.itemID] or 0)+v.amount) end
   rows[i]={templateId=item.templateId,required=item.required,owned=snap.stock[i],missing=missing,unitPrice=sum(unit),cost=cost,currencyId=0,unitCosts=unit,costs=costVector}
  end
  local budgets={};local affordable=true;for _,v in ipairs(snap.balances) do local n=totals[v.itemID] or 0;if n>v.amount then affordable=false end;budgets[#budgets+1]={itemID=v.itemID,amount=n} end
  capacity(items,needs,currency)
  return {status='ready',canAfford=affordable,buildId=p.buildId,manifestSHA256=p.manifestSHA256,currencyId=0,totalCost=total,wallet=snap.wallet,items=rows,costs=budgets,balances=snap.balances},items,snap
 end
 local function safe(fn) local ok,value=pcall(fn);if ok then return value end;return {status='unavailable',reason=tostring(value)} end
 local function clock() local n=d.monotonicSeconds();assert(type(n)=='number' and n==n and n>=0,'clock');return n end
 local function validID(id) return type(id)=='string' and #id==36 and id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') end
 local function public(op)
  local legs={};for i,l in ipairs(op.legs) do legs[i]={templateId=l.templateId,quantity=l.quantity,cost=l.cost,costs=l.costs,state=l.state,callbackCode=l.code,before=l.before,after=l.after} end
  return {currencyId=op.currency,status=op.state,operationUUID=op.id,buildId=op.buildId,manifestSHA256=op.manifest,totalBudget=op.budget,costs=op.costs,legs=legs,serverExactlyOnce=false}
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
  local exact=true
  for i,v in ipairs(l.before.balances) do
   local after=current.balances[i];assert(after and after.itemID==v.itemID,'resource_binding')
   local wanted=0;for _,c in ipairs(l.costs) do if c.itemID==v.itemID then wanted=c.amount end end
   local delta=v.amount-after.amount;if delta~=0 and delta~=wanted then op.state='uncertain';return end
   if delta~=wanted then exact=false end
  end
  if l.code==0 and current.stock[l.index]-l.before.stock[l.index]==l.quantity and charged==l.cost and exact then
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
   assert(operationCount<32,'operation_limit');local q,items,snap=quote(p);assert(q.canAfford,'insufficient_resource');integer(p.maxSpend);assert(p.maxSpend==q.totalCost and equalCosts(p.maxCosts,q.costs),'price_changed')
   local legs={};for i,item in ipairs(q.items) do if item.missing>0 then legs[#legs+1]={templateId=item.templateId,quantity=item.missing,cost=item.cost,costs=item.costs,index=i,state='new'} end end
   op={currency=p.currencyId,id=p.operationUUID,items=items,legs=legs,next=1,budget=q.totalCost,costs=q.costs,manifest=p.manifestSHA256,buildId=p.buildId,state=#legs==0 and 'complete' or 'ready'};ledger[op.id]=op;operationCount=operationCount+1
  end
  own();reconcile(op)
  assert(op.currency==p.currencyId and op.manifest==p.manifestSHA256 and op.buildId==p.buildId and op.budget==p.maxSpend and equalCosts(p.maxCosts,op.costs),'operation_changed')
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
  return {currencyId=op.currency,status='prepared',operationUUID=op.id,buildId=op.buildId,manifestSHA256=op.manifest,totalBudget=op.budget,leg=op.next,templateId=l.templateId,quantity=l.quantity,cost=l.cost,costs=l.costs,nonce=l.nonce,before=l.before}
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
  local offer=row(l.templateId);assert(equalCosts(l.costs,scaled(costs(offer),l.quantity)),'offer_changed')
  local command=offer.getWay==config('Common.Const.Const').HOMELAND_ORNAMENT_GET_WAY.REDEEM and 'RPC_CS_RedeemMultiOrnament' or 'RPC_CS_BuyMultiOrnament'
  local ok=pcall(d.serverMsg,m,command,l.templateId,l.quantity,function(code)
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

end)(),3)

if system.cmdPrefixes.atlasResidentialV11==nil then
 local api=(function()
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

end)().new(pg,package.loaded,{enabled=true})
 local module={}
 for _,name in ipairs({'checkBatch','getFacilities','placeOrnamentBatch'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 module.capabilities=function()return {ok=true,data={version=11,areaId=1,normalPlacementChecks=true}}end
 package.loaded['Atlas.Private.ResidentialV11']=module
 system:registerPrefix('atlasResidentialV11','Atlas.Private.ResidentialV11',{requireAuth=true})
end

if system.cmdPrefixes.atlasBuildSelectionV4==nil then
 local api=(function()
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

end)().new(pg,package.loaded)
 local module={}
 for _,name in ipairs({'state','select'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 package.loaded['Atlas.Private.BuildSelectionV4']=module
 system:registerPrefix('atlasBuildSelectionV4','Atlas.Private.BuildSelectionV4',{requireAuth=true})
end

local previousStorage=package.loaded['Atlas.Private.BuildStorageV1']
if system.cmdPrefixes.atlasBuildStorageV1==nil or previousStorage.contextMe~=pg.me or previousStorage.contextSpace~=pg.space or previousStorage.atlasRevision~='storage-20261026-r2' then
 if previousStorage then
  local history=package.loaded['Atlas.Private.BuildStorageHistory'] or {}
  assert(#history<128,'storage_context_limit');history[#history+1]=previousStorage;package.loaded['Atlas.Private.BuildStorageHistory']=history
 end
 local api=(function()
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

end)().new(pg,package.loaded)
 local module={contextMe=pg.me,contextSpace=pg.space,atlasRevision='storage-20261026-r2'}
 for _,name in ipairs({'capabilities','getFacilities','prepare','commit','status'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 package.loaded['Atlas.Private.BuildStorageV1']=module
 if system.cmdPrefixes.atlasBuildStorageV1 then assert(system.cmdPrefixes.atlasBuildStorageV1.requireAuth==true) else system:registerPrefix('atlasBuildStorageV1','Atlas.Private.BuildStorageV1',{requireAuth=true}) end
end

if system.cmdPrefixes.atlasBuildLibraryV2==nil then
 local api=(function()
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

end)().new(pg,package.loaded)
 local module={}
 for _,name in ipairs({'state','refresh','prepare','commit','status','zoneContext'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 package.loaded['Atlas.Private.BuildLibraryV2']=module
 system:registerPrefix('atlasBuildLibraryV2','Atlas.Private.BuildLibraryV2',{requireAuth=true})
end

if system.cmdPrefixes.atlasSeasonalV1==nil then
 local api=(function()
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

end)().new(pg,package.loaded,{enabled=true,areaID=2})
 local module={}
 for _,name in ipairs({'checkBatch','getFacilities','placeOrnamentBatch'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 module.capabilities=function()return {ok=true,data={version=1,areaId=2,normalPlacementChecks=true}}end
 package.loaded['Atlas.Private.SeasonalV1']=module
 system:registerPrefix('atlasSeasonalV1','Atlas.Private.SeasonalV1',{requireAuth=true})
end

if system.cmdPrefixes.atlasResidentialV12r2==nil then
 local api=(function()
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

end)().new(pg,package.loaded,{enabled=true,fullTransforms=true,areaID=1})
 local module={}
 for _,name in ipairs({'checkBatch','getFacilities','placeOrnamentBatch','inspectRotations','checkGeometry'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 module.capabilities=function()return {ok=true,data={version=12,areaId=1,fullTransforms=true,normalPlacementChecks=true}}end
 package.loaded['Atlas.Private.ResidentialV12r2']=module
 system:registerPrefix('atlasResidentialV12r2','Atlas.Private.ResidentialV12r2',{requireAuth=true})
end
