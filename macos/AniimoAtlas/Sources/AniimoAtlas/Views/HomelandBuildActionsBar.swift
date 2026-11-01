import SwiftUI

/// Transaction actions stay visible while the map or item list scrolls.
struct HomelandBuildActionsBar:View {
    @ObservedObject var store:HomelandBuildWorkflowStore
    @ObservedObject var connection:HomelandGameConnectionStore
    let section:Int
    let now:Date
    @State private var purchase=false
    @State private var placement=false
    var body:some View {
        HStack(spacing:12){
            if store.busy {ProgressView().controlSize(.small)}
            if store.savedImport {
                Label("Already imported",systemImage:"checkmark.seal.fill").foregroundStyle(.green)
                Spacer()
                Button("Select whole build in game",systemImage:"square.dashed.inset.filled"){Task{await store.selectWholeBuild(connection:connection)}}
                Button("Check saved import"){Task{await store.recoverImport(connection:connection)}}
                if let descriptor=store.importDescriptor,let receipt=try? HomelandBuildImportJournal(descriptor:descriptor).read(),receipt.phase=="verified" {
                    HomelandStoreButton(instances:Dictionary(uniqueKeysWithValues:receipt.imported.map{($0.id,$0.homeID)}),connection:connection,title:"Store whole build")
                }
            }else if section==1 && store.destination==0 {
                Text(store.placementChecked ? "Location passed game checks":"Drag the build, then check its location").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Check location",systemImage:"checkmark.shield"){Task{await store.checkPlacement(connection:connection)}}.disabled(!store.canImportArea || store.proposal==nil)
                Button("Place in Homeland",systemImage:"square.and.arrow.down"){placement=true}.buttonStyle(.borderedProminent).disabled(!store.placementChecked)
            }else if section==0 {
                Button("Check missing pieces",systemImage:"shippingbox"){Task{await store.refreshQuote(connection:connection)}}
                Spacer()
                if let quote=store.quote,quote.totalCost>0,!store.savedPurchase {
                    Button {purchase=true}label:{
                        HStack{Text("Buy missing");if let costs=quote.costs{ForEach(costs.filter{$0.amount>0}){cost in HomelandCurrencyIcon(id:cost.itemID,size:20);Text(cost.amount.formatted())}}else{HomelandCurrencyIcon(id:store.currencyID,size:20);Text(quote.totalCost.formatted())}}
                    }.buttonStyle(.borderedProminent).disabled(!quote.isAffordable || store.inventory?.isFresh(at:now) != true)
                }else if store.savedPurchase {Label("Purchase saved",systemImage:"bag.badge.checkmark");Button("Check saved purchase"){Task{await store.recoverPurchase(connection:connection)}}}
            }else {Text("Existing combos are preserved. Saving never buys or places furniture.").font(.caption).foregroundStyle(.secondary);Spacer()}
        }
        .disabled(store.busy || !connection.connected || (store.descriptor==nil && store.importDescriptor==nil))
        .confirmationDialog("Buy the missing pieces for \(store.quote?.costSummary ?? "the quoted resources")?",isPresented:$purchase,titleVisibility:.visible){Button("Confirm purchase"){Task{await store.purchase(connection:connection)}};Button("Cancel",role:.cancel){}}
        .confirmationDialog("Place this build in \(store.areaID==0 ? "Production":(store.areaID==1 ? "Residential":"Seasonal"))?",isPresented:$placement,titleVisibility:.visible){Button("Place in Homeland"){Task{await store.importBuild(connection:connection)}};Button("Cancel",role:.cancel){}}message:{Text("The game will recheck inventory, boundaries and collisions. Existing furniture is preserved.")}
    }
}
