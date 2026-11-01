from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3]
folder=Path(__file__).resolve().parent
header='''assert(pg and pg.me and pg.space and pg.me.space==pg.space and pg.space.demoMode==false and pg.space.homeLandOwnerPlayerId==pg.me.id)
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
'''
source=header
for version,file in [(1,'purchase.lua'),(2,'purchase-v2.lua'),(3,'purchase-v3.lua')]:
 suffix=str(version)+('r3' if version==3 else '')
 source+=f"install('atlasBuildWorkflowV{suffix}','Atlas.Private.BuildWorkflowV{suffix}',(function()\n"+(root/'tools/build-workflow'/file).read_text()+f'\nend)(),{version})\n'
source+="""
if system.cmdPrefixes.atlasResidentialV11==nil then
 local api=(function()
"""+(root/'tools/build-workflow/residential.lua').read_text()+"""
end)().new(pg,package.loaded,{enabled=true})
 local module={}
 for _,name in ipairs({'checkBatch','getFacilities','placeOrnamentBatch'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 module.capabilities=function()return {ok=true,data={version=11,areaId=1,normalPlacementChecks=true}}end
 package.loaded['Atlas.Private.ResidentialV11']=module
 system:registerPrefix('atlasResidentialV11','Atlas.Private.ResidentialV11',{requireAuth=true})
end
"""
source+="""
if system.cmdPrefixes.atlasBuildSelectionV4==nil then
 local api=(function()
"""+(root/'tools/build-workflow/selection.lua').read_text()+"""
end)().new(pg,package.loaded)
 local module={}
 for _,name in ipairs({'state','select'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 package.loaded['Atlas.Private.BuildSelectionV4']=module
 system:registerPrefix('atlasBuildSelectionV4','Atlas.Private.BuildSelectionV4',{requireAuth=true})
end
"""
source+="""
local previousStorage=package.loaded['Atlas.Private.BuildStorageV1']
if system.cmdPrefixes.atlasBuildStorageV1==nil or previousStorage.contextMe~=pg.me or previousStorage.contextSpace~=pg.space or previousStorage.atlasRevision~='storage-20261026-r2' then
 if previousStorage then
  local history=package.loaded['Atlas.Private.BuildStorageHistory'] or {}
  assert(#history<128,'storage_context_limit');history[#history+1]=previousStorage;package.loaded['Atlas.Private.BuildStorageHistory']=history
 end
 local api=(function()
"""+(root/'tools/build-workflow/storage.lua').read_text()+"""
end)().new(pg,package.loaded)
 local module={contextMe=pg.me,contextSpace=pg.space,atlasRevision='storage-20261026-r2'}
 for _,name in ipairs({'capabilities','getFacilities','prepare','commit','status'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 package.loaded['Atlas.Private.BuildStorageV1']=module
 if system.cmdPrefixes.atlasBuildStorageV1 then assert(system.cmdPrefixes.atlasBuildStorageV1.requireAuth==true) else system:registerPrefix('atlasBuildStorageV1','Atlas.Private.BuildStorageV1',{requireAuth=true}) end
end
"""
source+="""
if system.cmdPrefixes.atlasBuildLibraryV2==nil then
 local api=(function()
"""+(root/'tools/build-workflow/library.lua').read_text()+"""
end)().new(pg,package.loaded)
 local module={}
 for _,name in ipairs({'state','refresh','prepare','commit','status','zoneContext'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 package.loaded['Atlas.Private.BuildLibraryV2']=module
 system:registerPrefix('atlasBuildLibraryV2','Atlas.Private.BuildLibraryV2',{requireAuth=true})
end
"""
source+="""
if system.cmdPrefixes.atlasSeasonalV1==nil then
 local api=(function()
"""+(root/'tools/build-workflow/residential.lua').read_text()+"""
end)().new(pg,package.loaded,{enabled=true,areaID=2})
 local module={}
 for _,name in ipairs({'checkBatch','getFacilities','placeOrnamentBatch'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 module.capabilities=function()return {ok=true,data={version=1,areaId=2,normalPlacementChecks=true}}end
 package.loaded['Atlas.Private.SeasonalV1']=module
 system:registerPrefix('atlasSeasonalV1','Atlas.Private.SeasonalV1',{requireAuth=true})
end
"""

source+="""
if system.cmdPrefixes.atlasResidentialV12r2==nil then
 local api=(function()
"""+(root/'tools/build-workflow/residential.lua').read_text()+"""
end)().new(pg,package.loaded,{enabled=true,fullTransforms=true,areaID=1})
 local module={}
 for _,name in ipairs({'checkBatch','getFacilities','placeOrnamentBatch','inspectRotations','checkGeometry'})do local method=name;module[method]=function(s,c,p)return {ok=true,data=api[method](p)}end end
 module.capabilities=function()return {ok=true,data={version=12,areaId=1,fullTransforms=true,normalPlacementChecks=true}}end
 package.loaded['Atlas.Private.ResidentialV12r2']=module
 system:registerPrefix('atlasResidentialV12r2','Atlas.Private.ResidentialV12r2',{requireAuth=true})
end
"""

(folder/'registration.lua').write_text(source)
(folder/'fragment.h').write_text('static const char fixedFragment[]='+json.dumps(source,ensure_ascii=True)+';\n#define FRAGMENT_SHA256 '+json.dumps(hashlib.sha256(source.encode()).hexdigest())+'\n')
