import SwiftUI

struct HomelandBuildComboView:View {
    @ObservedObject var workflow:HomelandBuildWorkflowStore
    @ObservedObject var connection:HomelandGameConnectionStore
    @StateObject private var store=HomelandComboLibraryStore()
    @State private var confirming=false
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack {
                Label("Save to in-game Combos",systemImage:"square.stack.3d.up.fill").font(.headline)
                Spacer()
                Button("Refresh slots",systemImage:"arrow.clockwise"){Task{await store.refresh(connection:connection)}}.disabled(store.busy || !connection.connected)
            }
            if let library=store.library {
                HStack(spacing:24){Text("My combos: \(library.own.count)/\(library.ownLimit)");Text("Saved shared combos: \(library.saved.count)/\(library.savedLimit)")}.font(.callout.weight(.medium))
                DisclosureGroup("View current combos"){
                    VStack(alignment:.leading,spacing:8){
                        ForEach(library.own){row in HStack{Text(row.name.isEmpty ? "My combo":row.name);Spacer();Text("My combos").foregroundStyle(.secondary)}}
                        ForEach(library.saved){row in HStack{Text(row.name.isEmpty ? "Shared combo":row.name);Spacer();Text("Saved shared").foregroundStyle(.secondary)}}
                    }.font(.caption).padding(.top,8)
                }
                if store.hasPlacedBuild {
                    TextField("Combo name",text:$store.name).textFieldStyle(.roundedBorder).disabled(store.busy)
                    Text("Creates a shareable combo in your game’s My combos list from this build’s placed pieces. It does not move or buy anything.").font(.caption).foregroundStyle(.secondary)
                    if library.own.count>=library.ownLimit {Text("My combos is full. Choose a combo to remove through the game, then refresh. Atlas will not overwrite a saved design.").font(.caption).foregroundStyle(.orange)}
                }else if store.sharedCode != nil {
                    Text("Save the revealed shared build directly to Aniimo’s combo menu. No code typing is needed.").font(.caption).foregroundStyle(.secondary)
                    if library.saved.count>=library.savedLimit {Text("Saved shared combos is full. Free a slot in the game, then refresh. Existing combos are preserved.").font(.caption).foregroundStyle(.orange)}
                }else {
                    Text("A custom design must be placed once before the game can save it as a combo. The normal save path uses existing piece IDs. For community builds, reveal the code inside Atlas first.").font(.caption).foregroundStyle(.secondary)
                }
                if store.saved==nil {
                    Button(store.hasPlacedBuild ? "Save to My combos":"Save shared combo"){confirming=true}.buttonStyle(.borderedProminent).disabled(!store.canSave || !connection.connected)
                }
            }else{Text("Refresh slots to read your actual game library and available capacity.").font(.caption).foregroundStyle(.secondary)}
            if let saved=store.saved {
                Label(saved.phase=="complete" ? "Saved in Aniimo":"Saved operation needs verification",systemImage:saved.phase=="complete" ? "checkmark.seal.fill":"clock")
                if let code=saved.result?["code"]?.string {Text(code).font(.system(.body,design:.monospaced)).textSelection(.enabled)}
                Button("Check saved combo"){Task{await store.recover(connection:connection)}}.disabled(store.busy || !connection.connected)
            }
            if let message=store.message {Text(message).font(.callout).foregroundStyle(.secondary)}
            if store.busy {ProgressView().controlSize(.small)}
        }.padding(18).atlasGlass(cornerRadius:18)
        .task(id:workflow.importDescriptor?.manifestSHA256){store.configure(workflow.importDescriptor);if connection.connected {await store.refresh(connection:connection)}}
        .confirmationDialog(store.hasPlacedBuild ? "Create a shareable in-game combo?":"Save this shared combo in Aniimo?",isPresented:$confirming,titleVisibility:.visible){
            Button(store.hasPlacedBuild ? "Create shareable combo":"Save shared combo"){Task{await store.save(connection:connection)}}
            Button("Cancel",role:.cancel){}
        }message:{Text(store.hasPlacedBuild ? "‘\(store.name)’ will use one My combos slot and receive a game share code. Existing furniture and saved combos are unchanged.":"This uses one saved shared-combo slot. It does not purchase or place the build.")}
    }
}
