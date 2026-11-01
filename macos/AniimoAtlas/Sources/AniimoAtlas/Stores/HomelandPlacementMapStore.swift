import Foundation
import SceneKit
import simd

@MainActor final class HomelandPlacementMapStore:ObservableObject {
    @Published private(set) var scene:SCNScene?
    @Published private(set) var loading=false
    @Published private(set) var status="Read your Homeland to position this build among your existing furniture."
    @Published private(set) var capturedAt:Date?
    @Published private(set) var coverage:String?
    @Published private(set) var fresh=false
    private(set) var suggestedAnchor:SIMD3<Double>?
    private let workspace=LiveHomelandWorkspaceStore()
    private let loader=HomelandNativeSceneLoader()
    private var generation=UUID()
    private var ghost:SCNNode?
    private var center=SIMD3<Double>.zero
    private(set) var coordinates=HomelandPlacementCoordinates(originX:0,originZ:0)
    static let ghostCategory=1<<27

    func load(area:UInt8,source:HomelandScenePackage?,connection:HomelandGameConnectionStore,refresh:Bool) async {
        let connected=connection.connected
        let current=UUID();generation=current;scene=nil;ghost=nil;fresh=false;capturedAt=nil;coverage=nil;suggestedAnchor=nil;loading=true
        defer{if generation==current {loading=false}}
        guard let selected=HomelandCapturedArea(rawValue:area)else{return}
        status=refresh ? "Reading your current \(selected.tabTitle.lowercased())…":"Loading the last captured \(selected.tabTitle.lowercased())…"
        if refresh && connected {await workspace.readCurrentGame(area:selected)}
        else {await workspace.loadCapturedArea(selected)}
        guard current==generation,!Task.isCancelled else{return}
        guard case .ready(let session)=workspace.state else {
            if case .failed(let reason)=workspace.state {status=reason}else{status="The map is not available yet. Use Refresh map."};return
        }
        do {
            coordinates = .init(originX:session.verification.originX,originZ:session.verification.originZ)
            let map=try await loader.load(session.package){_,_ in}
            var boundariesAvailable=false
            if connected {
                do {
                    try await connection.preparePurchaseConnection(currencyID:0,requireLibrary:true)
                    let zones=try await connection.runBuildOperation{client,space in try await client.placementZones(expectedSpaceID:space)}
                    let selectedZones=zones.filter{$0.areaID==area}
                    for zone in selectedZones {addBoundary(zone,to:map)}
                    let rows=session.capture.rows.filter{$0.areaId==area}
                    let candidates=selectedZones.filter(\.unlocked).sorted{left,right in
                        func occupied(_ zone:HomelandPlacementZone)->Int {rows.filter{abs(Double($0.position[0])/100-zone.x)<zone.width/2 && abs(Double($0.position[2])/100-zone.z)<zone.depth/2}.count}
                        let a=occupied(left),b=occupied(right);return a==b ? left.id<right.id:a<b
                    }
                    if let candidate=candidates.first {suggestedAnchor=SIMD3(candidate.x,0,candidate.z)}
                    boundariesAvailable=true
                }catch{/* Furniture remains a real capture; unavailable boundaries are stated below. */}
            }
            guard current==generation,!Task.isCancelled else{return}
            if let source {
                let build=try await loader.load(source){_,_ in}
                guard let content=build.rootNode.childNode(withName:"Homeland content",recursively:false)else{throw HomelandSceneError.invalidScene("The build preview is unavailable.")}
                let wrapper=SCNNode();wrapper.name="Atlas proposed whole build";wrapper.opacity=0.78
                content.childNodes.forEach{wrapper.addChildNode($0.clone())}
                wrapper.enumerateChildNodes{node,_ in node.categoryBitMask=Self.ghostCategory}
                wrapper.categoryBitMask=Self.ghostCategory
                let bounds=wrapper.boundingBox
                let outline=SCNBox(width:CGFloat(max(0.1,bounds.max.x-bounds.min.x)),height:CGFloat(max(0.1,bounds.max.y-bounds.min.y)),length:CGFloat(max(0.1,bounds.max.z-bounds.min.z)),chamferRadius:0)
                let material=SCNMaterial();material.diffuse.contents=NSColor.systemGreen;material.emission.contents=NSColor.systemGreen;material.fillMode = .lines;material.lightingModel = .constant
                outline.materials=[material]
                let box=SCNNode(geometry:outline);box.name="Proposed build outline";box.categoryBitMask=Self.ghostCategory
                box.position=SCNVector3((bounds.min.x+bounds.max.x)/2,(bounds.min.y+bounds.max.y)/2,(bounds.min.z+bounds.max.z)/2)
                wrapper.addChildNode(box);map.rootNode.addChildNode(wrapper);ghost=wrapper
                center=SIMD3(source.scene.plot.center[0],source.scene.plot.center[1],source.scene.plot.center[2])
            }
            guard current==generation,!Task.isCancelled else{return}
            scene=map;capturedAt=session.capturedAt;coverage=(session.coverageMessage ?? "")+(boundariesAvailable ? " · unlocked plots outlined":" · live plot boundaries unavailable")
            fresh=refresh && connected && Date().timeIntervalSince(session.capturedAt)<90
            status=fresh ? "\(selected.tabTitle) map captured from game":"Saved \(selected.tabTitle) capture · refresh before placing"
        }catch{status=error.localizedDescription}
    }
    private func addBoundary(_ zone:HomelandPlacementZone,to scene:SCNScene){
        let shape=SCNBox(width:CGFloat(zone.depth),height:0.015,length:CGFloat(zone.width),chamferRadius:0)
        let material=SCNMaterial();material.lightingModel = .constant;material.fillMode = .lines
        material.diffuse.contents=zone.unlocked ? NSColor.systemGreen:NSColor.systemRed
        material.emission.contents=zone.unlocked ? NSColor.systemGreen:NSColor.systemRed
        shape.materials=[material]
        let node=SCNNode(geometry:shape);node.name="\(zone.unlocked ? "Unlocked":"Locked") plot \(zone.id)"
        let point=coordinates.native(x:zone.x,y:0.025,z:zone.z)
        node.simdPosition=SIMD3(Float(point.x),Float(point.y),Float(point.z));scene.rootNode.addChildNode(node)
    }
    func position(x:Double,y:Double,z:Double,yaw:Double,visible:Bool) {
        guard let ghost else{return};ghost.isHidden = !visible
        let anchor=coordinates.native(x:x,y:y,z:z)
        let rotation=simd_quatd(angle:yaw * .pi / 180,axis:SIMD3(0,1,0))
        let translation=anchor-rotation.act(center)
        ghost.simdPosition=SIMD3(Float(translation.x),Float(translation.y),Float(translation.z))
        ghost.simdOrientation=simd_quatf(angle:Float(yaw * .pi / 180),axis:SIMD3(0,1,0))
    }
}
