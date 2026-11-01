import SwiftUI

struct HomelandBuildWorkflowView: View {
    @ObservedObject var store: HomelandBuildWorkflowStore
    @ObservedObject var connection: HomelandGameConnectionStore
    var showPlacement = true
    @State private var inventoryNow = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let message=store.message {
                Text(message).font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(14).atlasGlass(cornerRadius:14)
            }
            if !store.savedImport,let quote = store.quote {
                liveQuote(quote)
            }
            if showPlacement {
            Picker("Destination",selection:$store.destination){
                Text("Place in Homeland").tag(0)
                Text("Save to in-game Combos").tag(1)
            }.pickerStyle(.segmented)
            if store.destination==1 {HomelandBuildComboView(workflow:store,connection:connection)}else{
            HStack(alignment: .top, spacing: 20) {
                location.frame(width: 270).disabled(store.busy)
                HomelandPlacementMapView(workflow:store,connection:connection)
            }
            }
            }
            if store.busy { ProgressView().controlSize(.small) }
        }
        .task {
            while !Task.isCancelled {
                inventoryNow = Date()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
        .onChange(of: connection.sessionProcessStart) { _, _ in store.invalidateSession() }
        .onChange(of: connection.connected) { _, connected in if !connected { store.invalidateSession() } }
    }
    private var location: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Placement", systemImage: "move.3d").font(.headline)
            Picker("Area", selection: $store.areaID) {
                Text("Production").tag(UInt8(0))
                Text("Residential").tag(UInt8(1))
                Text("Seasonal").tag(UInt8(2))
            }.disabled(store.busy)
            Text(store.canImportArea ? "Imports use the selected area’s normal inventory, bounds and collision checks. Unit-scale pieces are supported; Residential also preserves pitch and roll." : "Preview only. This area's editor origin and normal placement checks need live verification before importing.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !store.savedImport {
            StudioPositionControls(x: $store.x, y: $store.y, z: $store.z)
            Stepper("Rotation: \(Int(store.yaw))°", value: $store.yaw, in: 0...360, step: 90)
            }
            if store.proposal == nil { Text("These pieces or transforms cannot be prepared for the selected area.").font(.caption).foregroundStyle(.orange) }
            Text(store.savedImport ? "Showing your actual captured map. Select the whole build in Aniimo to move its existing pieces." : "Move the outlined build on your captured map, then check its location against the current game.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }.padding(18).atlasGlass(cornerRadius: 18)
    }
    private func liveQuote(_ quote: HomelandBuildLiveQuote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live missing-piece quote", systemImage: "checkmark.seal.fill").font(.headline)
                Spacer()
                if let costs=quote.costs {
                    ForEach(costs.filter{$0.amount>0}) {cost in
                        HomelandCurrencyAmount(id:cost.itemID,name:HomelandBuildLiveQuote.resourceName(cost.itemID),amount:cost.amount.formatted())
                    }
                } else { HomelandCurrencyAmount(id: Int64(quote.currencyId), name: store.currencyName, amount: quote.totalCost.formatted()) }
            }
            if store.inventory?.isFresh(at: inventoryNow) != true {
                Text("Inventory check expired. Check missing pieces again before purchasing.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let costs=quote.costs,let balances=quote.balances {
                ForEach(costs) {cost in
                    let available=balances.first(where:{$0.itemID==cost.itemID})?.amount ?? 0
                    if cost.amount>available {
                        Text("Need \((cost.amount-available).formatted()) more \(HomelandBuildLiveQuote.resourceName(cost.itemID))").foregroundStyle(.orange).font(.callout)
                    }
                }
            }
            ForEach(quote.items) { row in
                HStack {
                    HomelandItemIcon(id: UInt32(exactly: row.templateId), size: 32)
                    Text(store.itemNames[row.templateId] ?? "Item \(row.templateId)").font(.callout).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("Need \(row.required) · Spare \(row.owned) · Missing \(row.missing)").font(.caption)
                    if let costs=row.costs {
                        ForEach(costs.filter{$0.amount>0}) {cost in
                            HomelandCurrencyIcon(id:cost.itemID,size:18)
                            Text(cost.amount.formatted()).font(.callout.weight(.medium).monospacedDigit())
                        }
                    } else {
                        HomelandCurrencyIcon(id: Int64(row.currencyId), size: 18)
                        Text(row.cost.formatted()).font(.callout.weight(.medium).monospacedDigit())
                    }
                }
            }
        }.padding(18).atlasGlass(cornerRadius: 18)
    }
}
