local M=dofile('tools/build-workflow/purchase-v3.lua')
local ID='12345678-1234-1234-1234-123456789abc'
local function fixture()
 local money={[2]=100,[1011]=100,[4040030]=50,[4040033]=20};local calls={};local time=0
 local s={demoMode=false,homeLandOwnerPlayerId='mock',itemMap={}}
 local m={id='mock',space=s,serverArea=1,itemCountBindMap={},statHomelandOrnament={},statHomeCarOrnament={},homeBasicInfo={level=16},unlockedHomelandFurnitureMap={}}
 local c={INV_BOUND_TYPE_BOUND=1,INV_BOUND_TYPE_UNBOUND=2,ITEM_LOCKED_NOT=2,HOMELAND_ORNAMENT_GET_WAY={BUY=1,REDEEM=2}}
 local data={['Common.Const.Const']=c,['Common.Const.ItemConst']={INV_TYPE_SPECIAL=0},['Data.home_object_data']={},['Data.item_data']={},['Data.home_item_release_data']={},['Data.home_object_place_data']={},['Data.revert_home_place_data']={},['Data.homeland_area_data']={[0]={placeNumRatio=1}}}
 for _,id in ipairs({100,200,300}) do data['Data.home_object_data'][id]={buyMoneyType=id==100 and 2 or 1011,buyMoneyNum=2,getWay=1,maxNum=100,homelandAreaIds={0}};data['Data.item_data'][id]={invId=8} end
 local r=data['Data.home_object_data'][300];r.buyMoneyType=nil;r.buyMoneyNum=nil;r.getWay=2;r.buyItemId1=4040030;r.buyItemNum1=3;r.buyItemId2=4040033;r.buyItemNum2=2
 m.getItemCountById=function(self,id)assert(self==m);return money[id]or 0 end
 m.serverMsg=function(self,rpc,id,qty,cb)assert(self==m);calls[#calls+1]={rpc=rpc,id=id,qty=qty,cb=cb}end
 local api=M.new({me=m,space=s},data,{enabled=true,walletGetter=m.getItemCountById,serverMsg=m.serverMsg,monotonicSeconds=function()return time end})
 local request={currencyId=0,operationUUID=ID,buildId=999,manifestSHA256=string.rep('a',64),nonce=string.rep('1',64),items={{templateId=100,required=1},{templateId=200,required=2},{templateId=300,required=3}}}
 local function deliver(i)
  local l=calls[i];local o=data['Data.home_object_data'][l.id];l.cb(0);s.itemMap[l.id]=(s.itemMap[l.id]or 0)+l.qty
  if l.rpc=='RPC_CS_BuyMultiOrnament' then money[o.buyMoneyType]=money[o.buyMoneyType]-o.buyMoneyNum*l.qty
  else for n=1,2 do local id=o['buyItemId'..n];if id then money[id]=money[id]-o['buyItemNum'..n]*l.qty end end end
 end
 return api,request,calls,deliver,money,data,function(n)time=n end
end
local a,p,c,deliver,money,data,time=fixture();local q=a.quote(p);assert(q.status=='ready' and q.totalCost==21 and #q.costs==4)
p.maxSpend=q.totalCost;p.maxCosts=q.costs
local r=a.prepare(p);assert(r.status=='prepared' and #c==0)
local commit={operationUUID=ID,leg=1,nonce=r.nonce};a.commit(commit);a.commit(commit);assert(#c==1);deliver(1);assert(a.status({operationUUID=ID}).status=='ready')
for leg=2,3 do p.nonce=string.rep(tostring(leg),64);r=a.prepare(p);assert(r.status=='prepared' and r.leg==leg);a.commit({operationUUID=ID,leg=leg,nonce=r.nonce});deliver(leg)end
assert(a.status({operationUUID=ID}).status=='complete' and c[3].rpc=='RPC_CS_RedeemMultiOrnament' and money[4040030]==41 and money[4040033]==14)
-- Same numeric total in the wrong resources must never reconcile.
a,p,c,deliver,money,data,time=fixture();q=a.quote(p);p.maxSpend=q.totalCost;p.maxCosts=q.costs;r=a.prepare(p);a.commit({operationUUID=ID,leg=1,nonce=r.nonce});c[1].cb(0);money[1011]=98
assert(a.status({operationUUID=ID}).status=='uncertain' and #c==1)
-- Exact resource budgets, shortages and changed offer are rejected before sending.
a,p,c,deliver,money,data=fixture();q=a.quote(p);p.maxSpend=q.totalCost;p.maxCosts=q.costs;p.maxCosts[1].amount=p.maxCosts[1].amount+1
assert(a.prepare(p).status=='unavailable' and #c==0)
a,p,c,deliver,money,data=fixture();money[4040030]=1;q=a.quote(p);assert(q.status=='ready' and q.canAfford==false and #c==0)
a,p,c,deliver,money,data=fixture();data['Data.home_object_data'][100].buyMoneyType=4040033;data['Data.item_data'][4040033]={invId=8};q=a.quote(p);assert(q.status=='ready' and #q.costs==3)
print('PASS V3 MOCK: mixed money/material costs, two-material redemption, per-resource receipt validation, budget/shortage checks and duplicate suppression; no live purchase')
