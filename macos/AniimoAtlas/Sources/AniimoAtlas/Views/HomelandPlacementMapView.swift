import AppKit
import SceneKit
import SwiftUI
import simd

struct HomelandPlacementMapView:View {
    @ObservedObject var workflow:HomelandBuildWorkflowStore
    @ObservedObject var connection:HomelandGameConnectionStore
    @StateObject private var map=HomelandPlacementMapStore()
    @State private var localAnchor = SIMD4<Double>.zero

    var body:some View {
        VStack(alignment:.leading,spacing:10){
            HStack {
                Label(map.status,systemImage:map.fresh ? "checkmark.circle":"clock").font(.caption.weight(.medium))
                Spacer()
                Button("Last captured map",systemImage:"clock"){Task{await reload(refresh:false)}}
                    .disabled(map.loading || workflow.busy)
                Button("Refresh map",systemImage:"arrow.clockwise"){Task{await reload(refresh:true)}}
                    .disabled(map.loading || workflow.busy || !connection.connected)
            }
            if let scene=map.scene {
                HomelandPlacementViewport(
                    scene:scene,
                    coordinates:map.coordinates,
                    height:workflow.y,
                    anchor:localAnchor,
                    canDrag:!workflow.savedImport && !workflow.busy,
                    moved: { point in
                        localAnchor = SIMD4(point.x, workflow.y, point.z, workflow.yaw)
                        map.position(x: point.x, y: workflow.y, z: point.z, yaw: workflow.yaw, visible: true)
                    },
                    onMouseUp: {
                        workflow.x = localAnchor.x
                        workflow.z = localAnchor.z
                    }
                )
                .frame(minHeight:360,idealHeight:450).clipShape(RoundedRectangle(cornerRadius:18))
                    .accessibilityLabel("Captured Homeland map with whole-build placement preview")
            }else {
                VStack(spacing:12){if map.loading {ProgressView()};Text(map.status).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)}
                    .frame(maxWidth:.infinity,minHeight:320).atlasGlass(cornerRadius:18)
            }
            if let date=map.capturedAt {Text("Captured \(date.formatted(date:.abbreviated,time:.standard)) · \(map.coverage ?? "Coverage unavailable")").font(.caption2).foregroundStyle(.secondary)}
            Text(workflow.savedImport ? "This build was already imported. Use Select whole build in game to move its existing pieces." : "Drag the outlined build to position it. Drag empty space to orbit; scroll to zoom. Check location before importing.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
        .task(id:workflow.areaID){await reload(refresh:connection.connected)}
        .onChange(of:workflow.savedImport){_,_ in updatePosition()}
        .onAppear {
            localAnchor = SIMD4(workflow.x, workflow.y, workflow.z, workflow.yaw)
        }
        .onChange(of:workflow.yaw) { _, _ in updatePosition() }
        .onChange(of:workflow.y) { _, _ in updatePosition() }
        .onChange(of:workflow.x) { _, _ in updatePosition() }
        .onChange(of:workflow.z) { _, _ in updatePosition() }
    }
    private func reload(refresh:Bool)async {
        await map.load(area:workflow.areaID,source:workflow.placementSourcePackage,connection:connection,refresh:refresh)
        if let anchor=map.suggestedAnchor {workflow.suggestMapAnchor(anchor)}
        updatePosition()
    }
    private func updatePosition(){
        localAnchor = SIMD4(workflow.x, workflow.y, workflow.z, workflow.yaw)
        map.position(x:workflow.x,y:workflow.y,z:workflow.z,yaw:workflow.yaw,visible:!workflow.savedImport)
    }
}

private struct HomelandPlacementViewport:NSViewRepresentable {
    let scene:SCNScene
    let coordinates:HomelandPlacementCoordinates
    let height:Double
    let anchor:SIMD4<Double>
    let canDrag:Bool
    let moved:(SIMD3<Double>)->Void
    let onMouseUp: (() -> Void)?

    func makeNSView(context:Context)->HomelandBuildDragView {
        let view=HomelandBuildDragView();view.allowsCameraControl=true;view.autoenablesDefaultLighting=false
        view.antialiasingMode = .multisampling4X;view.preferredFramesPerSecond=60
        view.rendersContinuously=false;view.isPlaying=false
        view.onMouseUp = onMouseUp
        return view
    }
    func updateNSView(_ view:HomelandBuildDragView,context:Context){
        if view.scene !== scene {view.scene=scene}
        view.coordinates=coordinates;view.dragHeight=height;view.anchor=anchor;view.canDrag=canDrag;view.moved=moved


    }
}
private final class HomelandBuildDragView:SCNView {
    var coordinates=HomelandPlacementCoordinates(originX:0,originZ:0)
    var dragHeight=0.0
    var anchor=SIMD4<Double>.zero
    var canDrag=false
    var moved:((SIMD3<Double>)->Void)?
    var onMouseUp: (() -> Void)?
    private var startPoint:SIMD3<Double>?
    private var startAnchor=SIMD3<Double>.zero
    override func mouseDown(with event:NSEvent){
        let point=convert(event.locationInWindow,from:nil)
        let hits=hitTest(point,options:[.categoryBitMask:HomelandPlacementMapStore.ghostCategory])
        if canDrag,!hits.isEmpty,let ground=groundPoint(point){
            startPoint=ground;startAnchor=SIMD3(anchor.x, anchor.y, anchor.z);allowsCameraControl=false
        }else{super.mouseDown(with:event)}
    }
    override func mouseDragged(with event:NSEvent){
        guard let startPoint else{super.mouseDragged(with:event);return}
        guard let current=groundPoint(convert(event.locationInWindow,from:nil))else{return}
        moved?(HomelandPlacementDrag.position(anchor: startAnchor, start: startPoint, current: current))
    }
    override func mouseUp(with event:NSEvent){
        if let startPoint {
            defer { self.startPoint = nil; allowsCameraControl = true }
            if let current = groundPoint(convert(event.locationInWindow, from: nil)) {
                moved?(HomelandPlacementDrag.position(anchor: startAnchor, start: startPoint, current: current))
            }
            onMouseUp?()
        } else {
            super.mouseUp(with:event)
        }
    }
    private func groundPoint(_ point:NSPoint)->SIMD3<Double>? {
        let near=unprojectPoint(SCNVector3(point.x,point.y,0));let far=unprojectPoint(SCNVector3(point.x,point.y,1))
        guard let hit=HomelandPlacementCoordinates.groundPoint(near:SIMD3(Double(near.x),Double(near.y),Double(near.z)),far:SIMD3(Double(far.x),Double(far.y),Double(far.z)),height:dragHeight)else{return nil}
        return coordinates.local(hit)
    }
}
