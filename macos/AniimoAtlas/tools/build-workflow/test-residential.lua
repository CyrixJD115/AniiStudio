local factory=dofile('tools/build-workflow/residential.lua')
Vector3=function(x,y,z)return{x=x,y=y,z=z,isVector=true}end
local function fixture(wantedArea,fullTransforms)
 wantedArea=wantedArea or 1
 local source={LOCK_ZONE_AREA_ID=0};local checks=0;local calls=0;local ring={seq=10};local blocked=false
 function source._makeYawQuaternion(yaw)return Quaternion and Quaternion.Euler(0,yaw,0) or {eulerAngles={x=0,y=yaw,z=0}}end
 function source._getPlacementBoundSize(id,scale)assert(id==100);return{.5,.5}end
 function source._checkPlacementBoundsLocked()error('original Production bounds must not be called')end
 function source._validatePlacement(p,o)
  if fullTransforms then assert(p.yawAngle==nil and o.defaultRotation,'full quaternion must reach original validator') end
  assert(source.LOCK_ZONE_AREA_ID==wantedArea,'wrong_area_context');assert(pg.game.home.LOCK_ZONE_AREA_ID==wantedArea,'native_area_context');assert(pg.game.home:checkBoundsLock(wantedArea,Vector3(301,0,0),{}, {1,1})==false);assert(o.inventoryNeed==2 and o.countOffset>=0)
  assert(not source._checkPlacementBoundsLocked(100,{p.position.x,p.position.y,p.position.z},source._makeYawQuaternion(0),{1,1,1}));checks=checks+1;if blocked then return false,{reason='locked'}end
  return true,{homeId=p.homeTemplateId,pos=p.position,rotation=o.defaultRotation,geometry={x=p.position.x}}
 end
 function source._findCollidePreparedPlacement(p,earlier)for _,v in ipairs(earlier)do if v.geometry.x==p.geometry.x then return 1 end end end
 function source._isAddOrnamentLocked()return false end
 function source._ensureOrnamentCallbackHooks()end
 function source._getOrnamentResultRing()return ring end
 function source._serializeFacility(id)return{ornamentId=id,homeId=100,position={x=0,y=0,z=0},isTrash=false,yawAngle=0}end
 local home={LOCK_ZONE_AREA_ID=0}
 function home:checkBoundsLock(area,p)assert(self==home and area==wantedArea and p.x>=1 and p.x<=2);return false end
 function home:getLocalRotation(area,q)assert(area==wantedArea);return q end
 function home:getWorldPosition(area,p)assert(area==wantedArea);return Vector3(p.x+300,p.y,p.z)end
 function home:getLocalPosition(area,p)assert(area==wantedArea and p.isVector,'native vector required');return Vector3(p.x-300,p.y,p.z)end
 function home:getWorldRotation(area,q)assert(area==wantedArea);return q end
 local space={demoMode=false,homeLandOwnerPlayerId='mock',ornament={[1]={areaId=wantedArea}}}
 local owner={id='mock',space=space}
 function space:addOrnaments(items)assert(items[1].homeTemplateId==100 and items[1].homeId==nil and items[1].areaId==wantedArea and items[1].position.x==1 and items[1].position.isVector);calls=calls+1 end
 local loaded={['GameApp.CmdSocket.HomeCmdImplement']=source,['Common.Utils.HomeLandUtils']={buildOrnamentRotationFields=function(q)return q.eulerAngles.x*100,q.eulerAngles.y*100,q.eulerAngles.z*100 end},['Data.home_object_data']={[100]={canHomePlace=true,homelandAreaIds={0,1,2}}}}
 local pg={me=owner,space=space,game={home=home}}
 _G.pg=pg
 local api=factory.new(pg,loaded,{enabled=true,areaID=wantedArea,fullTransforms=fullTransforms})
 local p={areaId=wantedArea,items={{homeTemplateId=100,position={x=1,y=0,z=0},yawAngle=0,scale={x=1,y=1,z=1}},{homeTemplateId=100,position={x=2,y=0,z=0},yawAngle=0,scale={x=1,y=1,z=1}}}}
 return api,p,source,function()return calls end,function(v)blocked=v end
end
local a,p,source,calls,blocked=fixture()
assert(a.checkBatch(p).valid and calls()==0 and source.LOCK_ZONE_AREA_ID==0)
assert(a.getFacilities({}).facilities[1].areaId==1)
local result=a.placeOrnamentBatch(p);assert(result.dispatched and result.callbackSinceSeq==10 and calls()==1 and source.LOCK_ZONE_AREA_ID==0)
a,p,source,calls,blocked=fixture();blocked(true);assert(not a.checkBatch(p).valid and not a.placeOrnamentBatch(p).dispatched and calls()==0 and source.LOCK_ZONE_AREA_ID==0)
a,p,source,calls=fixture();p.areaId=0;assert(not a.checkBatch(p).valid and calls()==0)
a,p,source,calls=fixture();p.items[2].position.x=1;assert(not a.checkBatch(p).valid and calls()==0)
print('PASS residential MOCK: private area context, local/world roundtrip, bounds/inventory failure, batch collision, explicit area dispatch and original validator preserved; no live placement')

local seasonal,sp,ss,sc=fixture(2);assert(seasonal.checkBatch(sp).valid and seasonal.placeOrnamentBatch(sp).dispatched and sc()==1 and ss.LOCK_ZONE_AREA_ID==0)

Quaternion={Euler=function(x,y,z)local a,b,c=x*math.pi/360,y*math.pi/360,z*math.pi/360
 local sp,cp,sy,cy,sr,cr=math.sin(a),math.cos(a),math.sin(b),math.cos(b),math.sin(c),math.cos(c)
 return{eulerAngles={x=x,y=y,z=z},x=cy*sp*cr+sy*cp*sr,y=sy*cp*cr-cy*sp*sr,z=cy*cp*sr-sy*sp*cr,w=cy*cp*cr+sy*sp*sr}end,Angle=function(a,b)
 return math.max(math.abs(a.eulerAngles.x-b.eulerAngles.x),math.abs(a.eulerAngles.y-b.eulerAngles.y),math.abs(a.eulerAngles.z-b.eulerAngles.z)) end}
local full,fp,fs,fc=fixture(1,true)
fp.items[1].rotationCentidegrees={0,0,27000};fp.items[2].rotationCentidegrees={9000,0,0}
assert(full.inspectRotations(fp).valid and fc()==0)
local geometry=full.checkGeometry(fp);assert(geometry.valid and geometry.geometryOnly and geometry.inventoryVerified==false and fc()==0)
assert(full.checkBatch(fp).valid and fc()==0)
assert(full.placeOrnamentBatch(fp).dispatched and fc()==1 and fs.LOCK_ZONE_AREA_ID==0)
local bad,bp,bs,bc=fixture(1,true);bp.items[1].rotationCentidegrees={0,0,9000.5};assert(not bad.checkBatch(bp).valid and not bad.placeOrnamentBatch(bp).dispatched and bc()==0)
local legacy,lp,ls,lc=fixture();lp.items[1].rotationCentidegrees={9000,0,0};assert(not legacy.checkBatch(lp).valid and lc()==0)
local locked,kp,ks,kc,kblock=fixture(1,true);kblock(true);kp.items[1].rotationCentidegrees={9000,0,0};assert(not locked.checkGeometry(kp).valid and not locked.placeOrnamentBatch(kp).dispatched and kc()==0)
print('PASS full rotation MOCK: original quaternion validator routing, read-only geometry separation, strict rotation grid, legacy rejection, failure prevents dispatch')
