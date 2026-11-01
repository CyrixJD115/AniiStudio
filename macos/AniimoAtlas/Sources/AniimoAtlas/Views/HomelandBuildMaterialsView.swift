import SwiftUI

struct HomelandBuildMaterialsView: View {
    let scene: HomelandLayoutScene
    let server: HomelandServer
    @ObservedObject var gameConnection: HomelandGameConnectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var plan: HomelandBuildMaterialsPlan?
    @State private var localization: CachedHomelandLocalization?
    @State private var error: String?
    @State private var furnitureExpanded = true
    @State private var costsExpanded = true
    @State private var section = 0
    @State private var inventoryNow = Date()
    @StateObject private var workflow = HomelandBuildWorkflowStore()

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Build preparation", selection: $section) {
                Text("Requirements").tag(0)
                Text("Place & import").tag(1)
                Text("Activity").tag(2)
            }.pickerStyle(.segmented).padding(.horizontal, 26).padding(.bottom, 18)
            Divider().opacity(0.35)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    wallet
                    if section == 1 {
                        HomelandBuildWorkflowView(store: workflow, connection: gameConnection)
                    } else if section == 2 {
                        importActivity
                    } else if let plan {
                        HomelandBuildWorkflowView(store: workflow, connection: gameConnection, showPlacement: false)
                        HStack(alignment: .top, spacing: 20) {
                            requirements(plan).frame(maxWidth: .infinity, alignment: .topLeading)
                            VStack(alignment: .leading, spacing: 16) {
                                summary(plan)
                                if scene.n < 900_000_000 {
                                    HomelandBuildCodeView(server: server, number: scene.n)
                                        .padding(18).atlasGlass(cornerRadius: 18)
                                } else {
                                    Label("Local custom design",systemImage:"photo.artframe").padding(18).atlasGlass(cornerRadius:18)
                                }
                            }.frame(width: 260)
                        }
                    } else if let error {
                        ContentUnavailableView("Requirements unavailable", systemImage: "shippingbox", description: Text(error))
                    } else { ProgressView("Matching furniture and materials…").frame(maxWidth: .infinity).padding(40) }
                }.padding(24).frame(maxWidth: 1120).frame(maxWidth: .infinity)
            }
            Divider().opacity(0.35)
            HomelandBuildActionsBar(store:workflow,connection:gameConnection,section:section,now:inventoryNow)
                .padding(.horizontal,24).padding(.vertical,14)
        }
        .frame(width: 1120, height: 820)
        .background { StudioBackdrop() }
        .task { await load() }
        .task {
            while !Task.isCancelled {
                inventoryNow = Date()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
        .onChange(of: gameConnection.sessionProcessStart) { _, _ in workflow.invalidateSession() }
        .onChange(of: gameConnection.connected) { _, connected in if !connected { workflow.invalidateSession() } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill").font(.title2).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [StudioPalette.teal.opacity(0.18),StudioPalette.ocean.opacity(0.14),StudioPalette.lavender.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text("Build requirements").font(.title2.bold())
                Text("\(scene.n>=900_000_000 ? "Custom design":"Build #\(scene.n)") · \(server.name) · \(scene.instanceCount.formatted()) pieces")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.bordered)
        }.padding(.horizontal, 26).padding(.vertical, 20)
    }

    private var wallet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Your wallet", systemImage: "wallet.bifold").font(.headline)
                Spacer()
                if let plan {
                    Button("Refresh inventory", systemImage: "shippingbox.and.arrow.backward") { Task { await readStock(plan) } }
                        .controlSize(.small)
                        .disabled(workflow.busy || !gameConnection.connected || gameConnection.isReadingResources || gameConnection.isPurchasing)
                }
            }
            HomelandResourceBalancesView(connection: gameConnection)
        }.padding(18).atlasGlass(cornerRadius: 18)
    }

    private func requirements(_ plan: HomelandBuildMaterialsPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup(isExpanded: $furnitureExpanded) {
                VStack(spacing: 0) {
                    ForEach(plan.rows) { row in
                        furnitureRow(row)
                        if row.id != plan.rows.last?.id { Divider().opacity(0.3).padding(.vertical, 10) }
                    }
                }.padding(.top, 14)
            } label: {
                HStack {
                    Label("Furniture & pieces", systemImage: "cube.box.fill").font(.headline)
                    Spacer()
                    Text("\(plan.rows.count) types").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider().opacity(0.35)
            DisclosureGroup(isExpanded: $costsExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    if let funding = try? HomelandBuildFundingPlan.make(plan: plan, resources: gameConnection.connected ? gameConnection.resources : nil, now: inventoryNow, verifiedInventory: gameConnection.connected ? workflow.inventory : nil) {
                        ForEach(funding.rows) { row in
                            VStack(alignment: .leading, spacing: 5) {
                                HomelandCurrencyAmount(id: Int64(row.id), name: resourceName(row.id), amount: row.fullDesign.formatted())
                                Text("Full design: \(row.fullDesign.formatted()) · Missing pieces: \(row.missingPieces?.formatted() ?? "Check inventory")")
                                Text("Available: \(row.available?.formatted() ?? "Unverified") · Shortfall: \(row.shortfall?.formatted() ?? "Unverified")")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if plan.configuredTotals.isEmpty { Text("No configured costs found").font(.caption).foregroundStyle(.secondary) }
                }.padding(.top, 14)
            } label: {
                Label("Currencies & materials", systemImage: "square.stack.3d.up.fill").font(.headline)
            }
        }.padding(18).atlasGlass(cornerRadius: 18)
    }

    private func furnitureRow(_ row: HomelandBuildMaterialsPlan.Row) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    metric("Required", "\(row.count)")
                    metric("Spare", spare(row).map { $0.formatted() } ?? "Unverified")
                    metric("Missing", spare(row).map { max(0,Int64(row.count)-$0).formatted() } ?? "Check in game")
                }
                if row.candidates.isEmpty {
                    Label("No matching installed furniture", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if row.exactObject == nil {
                    Text("\(row.candidates.count) possible templates or levels. Direct purchase needs an exact template match.").foregroundStyle(.orange)
                }
                if let costs = row.unitCosts {
                    ForEach(costs, id: \.itemID) { cost in
                        HStack(spacing: 8) {
                            HomelandCurrencyIcon(id: Int64(cost.itemID), size: 22)
                            Text("\(cost.amount.formatted()) \(resourceName(cost.itemID)) each")
                            Spacer()
                            Text("\((cost.amount * row.count).formatted()) total").fontWeight(.medium)
                        }
                    }
                } else { Text("Price not indexed").foregroundStyle(.secondary) }
                Text(row.prefab).font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
            }.font(.caption).padding(.leading, 4).padding(.vertical, 12)
        } label: {
            HStack(spacing: 10) {
                HomelandItemIcon(id: row.exactObject?.id, size: 32)
                Text(row.exactObject.flatMap { localization?.name(for: $0) } ?? row.prefab)
                    .font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("×\(row.count)").font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }
    }

    private func summary(_ plan: HomelandBuildMaterialsPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Cost overview", systemImage: "list.bullet.rectangle").font(.headline)
            Text(plan.completeConfiguredCost ? "Full design estimate" : "Partial estimate")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(plan.configuredTotals, id: \.itemID) { cost in
                HomelandCurrencyAmount(id: Int64(cost.itemID), name: resourceName(cost.itemID), amount: cost.amount.formatted())
            }
            Divider().opacity(0.35)
            if let estimate = try? HomelandPurchaseService.estimate(plan: plan, resources: gameConnection.connected ? gameConnection.resources : nil, now: inventoryNow, verifiedInventory: gameConnection.connected ? workflow.inventory : nil), estimate.complete {
                Text("Estimated missing-piece cost").font(.caption).foregroundStyle(.secondary)
                ForEach(estimate.totals, id: \.itemID) { cost in
                    HomelandCurrencyAmount(id: Int64(cost.itemID), name: resourceName(cost.itemID), amount: cost.amount.formatted())
                }
            } else {
                Text("Read current spare inventory to calculate what you still need.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Configured prices are shown here. Purchases require a fresh live quote and your confirmation.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }.padding(18).atlasGlass(cornerRadius: 18)
    }

    private var importActivity: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Import verification", systemImage: "checkmark.shield.fill").font(.headline)
            if let checked = gameConnection.presenceCheckedAt {
                Text("Automatic area check: \(checked.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = gameConnection.connectionMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            if workflow.savedPurchase || workflow.savedImport {
                VStack(alignment: .leading, spacing: 12) {
                    if workflow.savedPurchase {
                        Label(workflow.purchasePhase == "complete" ? "Purchase delivered and verified" : "Saved purchase needs review", systemImage: "bag")
                        if let recovery = workflow.recovery {
                            Text("\(recovery.verifiedPieces) pieces delivered · \(recovery.unresolvedPieces) remaining or unresolved").font(.caption)
                            ForEach(recovery.rows) { row in
                                HStack {
                                    Text(workflow.itemNames[row.id] ?? "Item \(row.id)")
                                    Spacer()
                                    Text("×\(row.quantity) · \(row.state.rawValue)")
                                }.font(.caption)
                            }
                        }
                        Button("Check saved purchase") { Task { await workflow.recoverPurchase(connection: gameConnection) } }
                    }
                    if workflow.savedImport {
                        Label(workflow.importPhase == "verified" ? "Import positions verified" : "Saved import needs readback", systemImage: "square.and.arrow.down")
                        Button("Check saved import") { Task { await workflow.recoverImport(connection: gameConnection) } }
                    }
                    Text("Checking a saved operation never buys or imports it again.").font(.caption).foregroundStyle(.secondary)
                    if let message = workflow.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                }.padding(18).atlasGlass(cornerRadius: 18)
                    .disabled(workflow.busy || !gameConnection.connected)
            }
            let records = gameConnection.importVerifications.filter { $0.buildNumber == scene.n && $0.server == server }
            if records.isEmpty {
                Text("Verified imports will appear here with readback and persistence status.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(records) { record in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(record.expected.count) pieces · Build #\(record.buildNumber)").font(.headline)
                        Spacer()
                        Button("Verify now") { Task { await gameConnection.verifySavedImport(record.id) } }
                            .disabled(!gameConnection.connected || gameConnection.isPurchasing || gameConnection.isCheckingReturn)
                    }
                    Text(persistenceLabel(record.state)).font(.callout)
                    if let date = record.lastVerifiedAt {
                        Text("Read back \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(18).atlasGlass(cornerRadius: 18)
            }
            if scene.n == 1549 {
                DisclosureGroup("Earlier test controls") {
                    HomelandBuildActionControls(scene: scene, server: server, gameConnection: gameConnection).padding(.top, 12)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func persistenceLabel(_ state: HomelandImportPersistence) -> String {
        switch state {
        case .awaitingReturn: return "Positions verified. Leave Homeland and return to check saved placement."
        case .departed: return "Departure observed. Waiting for your return to Homeland."
        case .verifiedAfterReturn: return "Verified after leaving and returning to Homeland."
        case .verifiedAfterRestart: return "Verified after a new game process started."
        case .mismatch: return "A saved placement differs. No replacement or retry was sent."
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).foregroundStyle(.secondary); Text(value).fontWeight(.semibold).monospacedDigit() }
    }
    private func spare(_ row: HomelandBuildMaterialsPlan.Row) -> Int64? {
        guard gameConnection.connected, let object = row.exactObject else { return nil }
        if let verified = workflow.inventory?.spare(for: object.id, at: inventoryNow) { return verified }
        guard let snapshot = gameConnection.resources, (0...30).contains(inventoryNow.timeIntervalSince(snapshot.checkedAt)) else { return nil }
        return snapshot.stock.first(where: { $0.id == Int64(object.id) })?.confirmedPositiveCount
    }
    private func load() async {
        workflow.configure(scene: scene, server: server)
        guard let catalog = GameContentIndexService().loadCachedObjectCatalog() else {
            error = "Index your installed game in Content Index to match furniture and prices."
            return
        }
        localization = HomelandLocalizationService().load(buildDigest: catalog.buildDigest)
        do {
            let result = try HomelandBuildMaterialsPlan.make(scene: scene, catalog: catalog.catalog)
            plan = result
            if gameConnection.connected { await readStock(result) }
        } catch { self.error = error.localizedDescription }
    }
    private func readStock(_ plan: HomelandBuildMaterialsPlan) async {
        let furniture = plan.rows.compactMap { $0.exactObject.map { Int64($0.id) } }
        let materials = plan.configuredTotals.map { Int64($0.itemID) }.filter { ![Int64(1),2,1010,1011].contains($0) }
        guard !workflow.busy else { return }
        await gameConnection.refreshResources(stockItemIDs: Array(Set(furniture + materials)).sorted())
        if workflow.descriptor != nil && !workflow.savedImport { await workflow.refreshQuote(connection: gameConnection) }
        inventoryNow = Date()
    }
    private func resourceName(_ id: UInt32) -> String { localization?.currencyName(for: id) ?? "Item \(id)" }
}
