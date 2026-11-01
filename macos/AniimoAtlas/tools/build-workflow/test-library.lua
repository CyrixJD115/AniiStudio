local factory=dofile('tools/build-workflow/library.lua')
local function fixture(count)
 local now=100;CS={UnityEngine={Time={realtimeSinceStartup=now}}}
 local owned={};for i=1,count do owned[i]={_id='old'..i,name='Existing',ornaments={}}end
 local saved={};local calls=0;local owner={id='owner'};local space={demoMode=false,homeLandOwnerPlayerId='owner',ornament={}}
 owner.space=space;for i=1,2 do space.ornament[i]={areaId=1}end
 function owner:getHomeBlueprintCachedList(kind)return kind==1 and owned or saved end
 function owner:getHomeBlueprintTabList(kind,start,limit,done)assert(limit==50);done(0)end
 function owner:uploadHomeBlueprint(ids,name,description,covers,range,done)assert(#ids==2 and #range==3 and #covers==0);calls=calls+1;owned[#owned+1]={_id='ABCDEFGH',name=name,ornaments={{homeId=100},{homeId=100}}};done(0)end
 function owner:saveOtherHomeBlueprint(code,done)calls=calls+1;saved[#saved+1]={_id='saved-new',name='Shared',code=code};done(0)end
 local home={editor={calcEntitiesBounds=function()return 0,2,0,1,0,3 end},getHomeEntity=function()return{homeTemplateId=100}end}
 local pg={me=owner,space=space,game={home=home}}
 local utils={getUploadBlueprintLimit=function()return 15 end,getSavedOtherBlueprintLimit=function()return 15 end,getConfig=function(key)return key=='maxFurniturePerBlueprint' and 500 or 20 end}
 local modules={['Common.Homeland.HomeBlueprintUtils']=utils,['Common.Const.HomeBlueprintConst']={SOURCE_TYPE={UPLOADED=1,SAVED_OTHER=3}},['GameApp.CmdSocket.HomeCmdImplement']={_serializeFacility=function()return{homeId=100,isTrash=false}end}}
 local api=factory.new(pg,modules);api.refresh()
 local p={operationUUID=string.rep('a',36),nonce=string.rep('b',36),mode='placed',name='Apple',shareable=true,areaId=1,items={{id=1,homeID=100},{id=2,homeID=100}}}
 return api,p,function()return calls end
end
local a,p,calls=fixture(11);assert(a.state().ownLimit==15 and #a.state().own==11);assert(a.prepare(p).phase=='ready' and calls()==0);assert(a.commit(p).phase=='complete' and calls()==1);assert(not a.commit(p).valid and calls()==1)
a,p,calls=fixture(15);assert(not a.prepare(p).valid and calls()==0)
a,p,calls=fixture(0);p.shareable=false;assert(not a.prepare(p).valid and calls()==0)
a,p,calls=fixture(0);p.mode='shared';p.code='ABCDEFGH';assert(a.prepare(p).valid);assert(a.commit(p).phase=='complete' and calls()==1)
print('PASS combo-library MOCK: separate15-slot caps, exact placed IDs, explicit shareable consent, one dispatch, no overwrite or replay, normal shared-code save')
