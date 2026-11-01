local M=dofile('tools/build-workflow/purchase-v2.lua')
local ID='12345678-1234-1234-1234-123456789abc'
local function fixture(owned,currency)
 currency=currency or 1010
 local s={demoMode=false,homeLandOwnerPlayerId='mock',itemMap=owned or {}}
 local m={id='mock',space=s,serverArea=1,itemCountBindMap={},statHomelandOrnament={},statHomeCarOrnament={},homeBasicInfo={level=16},unlockedHomelandFurnitureMap={}}
 local c={INV_BOUND_TYPE_BOUND=1,INV_BOUND_TYPE_UNBOUND=2,ITEM_LOCKED_NOT=2,HOMELAND_ORNAMENT_GET_WAY={BUY=1}}
 local data={['Common.Const.Const']=c,['Common.Const.ItemConst']={INV_TYPE_SPECIAL=0},['Data.home_object_data']={},['Data.item_data']={},['Data.home_item_release_data']={},['Data.home_object_place_data']={},['Data.revert_home_place_data']={},['Data.homeland_area_data']={[0]={placeNumRatio=1}}}
 for _,id in ipairs({100,200}) do data['Data.home_object_data'][id]={buyMoneyType=currency,buyMoneyNum=2,getWay=1,placeId=id,homelandAreaIds={0}};data['Data.item_data'][id]={invId=8};data['Data.home_object_place_data'][id]={[16]={getWay=100}};data['Data.revert_home_place_data'][id]={id} end
 local money,time,calls=100,0,{}
 m.getItemCountById=function(self,id)assert(self==m and id==currency);return money end
 m.serverMsg=function(self,rpc,id,qty,cb)assert(self==m and rpc=='RPC_CS_BuyMultiOrnament');calls[#calls+1]={id=id,qty=qty,cb=cb} end
 local p={me=m,space=s};local d={enabled=true,walletGetter=m.getItemCountById,serverMsg=m.serverMsg,monotonicSeconds=function()return time end}
 local api=M.new(p,data,d)
 local request={currencyId=currency,operationUUID=ID,buildId=2444,manifestSHA256=string.rep('a',64),maxSpend=10,nonce=string.rep('1',64),items={{templateId=100,required=3},{templateId=200,required=2}}}
 return {api=api,p=p,data=data,request=request,calls=calls,deliver=function(i)local q=calls[i];q.cb(0);s.itemMap[q.id]=(s.itemMap[q.id]or 0)+q.qty;money=money-2*q.qty end,time=function(n)time=n end,wallet=function(n)money=n end}
end
local f=fixture({[100]=1});local q=f.api.quote(f.request);assert(q.status=='ready' and q.totalCost==8 and q.items[1].missing==2)
f.request.maxSpend=8;local r=f.api.prepare(f.request);assert(r.status=='prepared' and r.quantity==2 and r.cost==4 and #f.calls==0)
local commit={operationUUID=ID,leg=1,nonce=r.nonce};assert(f.api.commit(commit).status=='pending' and #f.calls==1)
f.api.commit(commit);assert(#f.calls==1);f.deliver(1);assert(f.api.status({operationUUID=ID}).status=='ready')
f.request.nonce=string.rep('2',64);r=f.api.prepare(f.request);assert(r.leg==2 and r.quantity==2)
f.api.commit({operationUUID=ID,leg=2,nonce=r.nonce});f.deliver(2);local done=f.api.status({operationUUID=ID});assert(done.status=='complete' and done.legs[2].after.wallet==92)
f.api.commit(commit);assert(#f.calls==2)
-- Shared-group requirements are combined before the cap check.
f=fixture();f.data['Data.home_object_data'][200].placeId=100;f.data['Data.revert_home_place_data'][100]={100,200};f.data['Data.home_object_place_data'][100][16].getWay=4
assert(f.api.quote(f.request).status=='unavailable' and #f.calls==0)
-- Wrong cap, changed snapshot, expired reservation, callback loss, or rejection never resend.
f=fixture();f.request.maxSpend=11;assert(f.api.prepare(f.request).status=='unavailable' and #f.calls==0)
f=fixture();r=f.api.prepare(f.request);f.wallet(99);assert(f.api.commit({operationUUID=ID,leg=1,nonce=r.nonce}).status=='unavailable' and #f.calls==0)
f=fixture();r=f.api.prepare(f.request);f.time(31);assert(f.api.commit({operationUUID=ID,leg=1,nonce=r.nonce}).status=='uncertain' and #f.calls==0)
f=fixture();r=f.api.prepare(f.request);f.api.commit({operationUUID=ID,leg=1,nonce=r.nonce});f.time(31);assert(f.api.status({operationUUID=ID}).status=='uncertain');f.api.commit({operationUUID=ID,leg=1,nonce=r.nonce});assert(#f.calls==1)
f=fixture();r=f.api.prepare(f.request);f.api.commit({operationUUID=ID,leg=1,nonce=r.nonce});f.calls[1].cb(17);assert(f.api.status({operationUUID=ID}).status=='rejected');f.api.commit({operationUUID=ID,leg=1,nonce=r.nonce});assert(#f.calls==1)
-- Fully owned builds cost zero and dispatch no purchases.
f=fixture({[100]=3,[200]=2});f.request.maxSpend=0;assert(f.api.quote(f.request).totalCost==0 and f.api.prepare(f.request).status=='complete' and #f.calls==0)
print('PASS: multi-item shortages, budget, shared capacity, serial receipts, duplicate suppression, stale state, timeout/reject, and zero-purchase owned builds; MOCK ONLY')

for _,currency in ipairs({1,2,1010,1011}) do
 f=fixture(nil,currency);q=f.api.quote(f.request);assert(q.currencyId==currency and q.items[1].currencyId==currency)
 r=f.api.prepare(f.request);assert(r.currencyId==currency);f.api.commit({operationUUID=ID,leg=1,nonce=r.nonce});f.deliver(1)
 assert(f.api.status({operationUUID=ID}).currencyId==currency)
end
f=fixture();f.request.currencyId=4040033;assert(f.api.quote(f.request).status=='unavailable' and #f.calls==0)
f=fixture();r=f.api.prepare(f.request);f.request.currencyId=2;assert(f.api.prepare(f.request).status=='unavailable' and #f.calls==0)
print('PASS V2: four ordinary currencies and currency-switch rejection; MOCK ONLY')

-- Partial replication remains halted; later exact readback can identify the delivered leg without resending.
f=fixture();r=f.api.prepare(f.request);f.api.commit({operationUUID=ID,leg=1,nonce=r.nonce})
f.calls[1].cb(0);f.p.space.itemMap[100]=1;f.wallet(99)
assert(f.api.status({operationUUID=ID}).status=='uncertain')
f.p.space.itemMap[100]=3;f.wallet(94)
local recovered=f.api.status({operationUUID=ID});assert(recovered.status=='uncertain' and recovered.legs[1].state=='reconciled')
assert(f.api.prepare(f.request).status=='uncertain' and #f.calls==1)
-- A late callback is read back, but an unsubmitted second leg is never continued automatically.
f=fixture();r=f.api.prepare(f.request);f.api.commit({operationUUID=ID,leg=1,nonce=r.nonce});f.time(31)
assert(f.api.status({operationUUID=ID}).status=='uncertain');f.deliver(1)
assert(f.api.status({operationUUID=ID}).legs[1].state=='reconciled' and #f.calls==1)
print('PASS V2: partial and late deliveries remain halted, with exact read-only reconciliation; MOCK ONLY')
