import SwiftUI

@MainActor final class HomelandBuildWorkflowStore: ObservableObject {
    @Published private(set) var descriptor: HomelandBuildTransactionDescriptor?
    @Published private(set) var importDescriptor: HomelandBuildTransactionDescriptor?
    @Published var destination=0
    private var mapAnchorInitialized=false
    func suggestMapAnchor(_ anchor:SIMD3<Double>){guard !savedImport,!mapAnchorInitialized else{return};x=anchor.x;z=anchor.z;mapAnchorInitialized=true}
    @Published private(set) var recovery: HomelandBuildRecoverySummary?
    @Published var areaID: UInt8 = 0 { didSet { placementChecked = false;mapAnchorInitialized=false } }
    var canImportArea: Bool { areaID <= 2 }
    var currencyID: Int64 { descriptor?.currencyID ?? 1011 }
    var currencyName: String { switch currencyID { case 0: return "resources"; case 1: return "Glimmer"; case 2: return "Credits"; case 1010: return "Home Coin"; default: return "Bud Tickets" } }
    @Published private(set) var quote: HomelandBuildLiveQuote?
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var placementChecked = false
    @Published private(set) var quoteTime: Date?
    @Published private(set) var savedPurchase = false
    @Published private(set) var savedImport = false
    @Published private(set) var purchasePhase: String?
    @Published private(set) var importPhase: String?
    @Published var x = 30.0 { didSet { placementChecked = false;mapAnchorInitialized=true } }
    @Published var y = 0.0 { didSet { placementChecked = false } }
    @Published var z = 22.5 { didSet { placementChecked = false;mapAnchorInitialized=true } }
    @Published var yaw = 90.0 { didSet { placementChecked = false } }
    private var source: HomelandLayoutScene?
    private var catalog: HomelandObjectCatalog?
    private var package: HomelandScenePackage?
    @Published private(set) var itemNames: [Int64: String] = [:]

    var inventory: HomelandBuildInventorySnapshot? {
        guard let quote, let quoteTime else { return nil }
        return HomelandBuildInventorySnapshot(quote: quote, checkedAt: quoteTime)
    }

    var proposal: HomelandBuildPlacementPlan? {
        guard let source, let catalog else { return nil }
        return try? HomelandBuildPlacementPlan.make(scene: source, catalog: catalog, areaID: areaID,
            worldAnchor: SIMD3(x,y,z), nativeYawDegrees: yaw, originX: 0, originZ: 0, alignTranslationToGrid: true)
    }
    var placementSourcePackage:HomelandScenePackage? {package}
    var preview: HomelandScenePackage? {
        guard let package, let plan = proposal else { return nil }
        let grouped = Dictionary(grouping: plan.pieces, by: \.prefab).mapValues { $0.map(\.nativeMatrix) }
        let scene = HomelandLayoutScene(n: package.scene.n,
            plot: .init(center: [z,y,x], size: package.scene.plot.size), placements: grouped, models: package.scene.models)
        return HomelandScenePackage(scene: scene, modelFiles: package.modelFiles)
    }
    func configure(scene: HomelandLayoutScene, server: HomelandServer) {
        guard !busy else { return }
        source = scene; descriptor = nil; importDescriptor = nil; recovery = nil; catalog = nil; package = nil
        quote = nil; quoteTime = nil; placementChecked = false; message = nil
        savedPurchase = false; savedImport = false; purchasePhase = nil; importPhase = nil; itemNames = [:]
        guard let cache = GameContentIndexService().loadCachedObjectCatalog() else {
            message = "Index your installed game before preparing an import."; return
        }
        catalog = cache.catalog
            package = HomelandSceneService().cachedPackage(build: HomelandBuild(server: server, number: scene.n, kind: "", designer: "", rvLevel: nil, likes: 0, previewURL: nil))
        do {
            importDescriptor = try? HomelandBuildTransactionDescriptor.make(scene: scene, server: server, catalog: cache.catalog, purchaseOnly: false)
            do { descriptor = try HomelandBuildTransactionDescriptor.make(scene: scene, server: server, catalog: cache.catalog) }
            catch { message = error.localizedDescription }
            guard let value=descriptor ?? importDescriptor else {return}
            if let text = HomelandLocalizationService().load(buildDigest: cache.buildDigest) {
                itemNames = Dictionary(uniqueKeysWithValues: cache.catalog.objects.compactMap { object in
                    text.name(for: object).map { (Int64(object.id), $0) }
                })
            }
            let purchase = try HomelandBuildTransactionJournal(descriptor: value).read()
            let imported = try HomelandBuildImportJournal(descriptor: value).read()
            recovery = purchase.map(HomelandBuildRecoverySummary.init)
            savedPurchase = purchase != nil; purchasePhase = purchase?.phase
            savedImport = imported != nil; importPhase = imported?.phase
            if let imported {areaID=imported.plan.areaID;message="This build is already in your Homeland. Select its existing pieces to move it; no purchase or duplicate import is needed."}
        } catch { message = error.localizedDescription }
    }
    func invalidateSession() {
        quote = nil; quoteTime = nil; placementChecked = false
        if !busy { message = "Reconnect and refresh the quote and location checks for the current game session." }
    }
    func refreshQuote(connection: HomelandGameConnectionStore) async {
        guard !busy, let descriptor else { return }
        busy = true; defer { busy = false }
        quote = nil; quoteTime = nil; message = "Checking exact spare inventory, live offers and capacity…"
        do {
            try await readQuote(connection: connection, descriptor: descriptor)
            guard let value = quote else { return }
            message = savedImport ? "This build was already imported. Inventory shows spare pieces only; its placed pieces are not missing." : !value.isAffordable ? "Some required resources are missing. Review the shortfalls below before purchasing." : value.totalCost == 0 ? "You already own every required piece. No purchase is needed." : "Live quote ready. Only missing pieces will be purchased."
            savedPurchase = try HomelandBuildTransactionJournal(descriptor: descriptor).read() != nil
        } catch { message = "A live quote is unavailable. The item may be locked, use unsupported costs, or need a refreshed game bridge. No purchase was sent." }
    }
    private func readQuote(connection: HomelandGameConnectionStore, descriptor: HomelandBuildTransactionDescriptor) async throws {
        await connection.refreshResources()
        try await connection.preparePurchaseConnection(currencyID:descriptor.currencyID)
        let value = try await connection.runBuildOperation { client, space in
            try await client.buildQuote(descriptor, expectedSpaceID: space)
        }
        quote = value; quoteTime = Date()
    }
    private func refreshAfterOperation(connection: HomelandGameConnectionStore) async {
        quote = nil; quoteTime = nil
        guard let descriptor else { return }
        // A failed readback must never obscure the durable transaction result or trigger a retry.
        try? await readQuote(connection: connection, descriptor: descriptor)
    }
    func purchase(connection: HomelandGameConnectionStore) async {
        guard !busy, !savedPurchase, let descriptor, let quote, quote.totalCost > 0,quote.isAffordable, let quoteTime else { return }
        guard Date().timeIntervalSince(quoteTime) <= 30 else {
            await refreshQuote(connection: connection)
            message = "Quote refreshed. Review the current total before confirming again."
            return
        }
        busy = true; defer { busy = false }
        message = "Waiting for purchase callbacks and exact inventory/wallet readback…"
        do {
            let journal = try HomelandBuildTransactionJournal(descriptor: descriptor)
            let receipt = try await connection.runBuildOperation { client, space in
                try await client.purchaseBuild(descriptor, quote: quote, expectedSpaceID: space, journal: journal)
            }
            recovery = HomelandBuildRecoverySummary(receipt)
            savedPurchase = true; purchasePhase = receipt.phase; self.quote = nil
            message = receipt.phase == "complete" ? "Missing pieces delivered · \(quote.costSummary) charged and verified." : "Purchase requires review. No automatic retry will be sent."
            await refreshAfterOperation(connection: connection)
        } catch {
            savedPurchase = (try? HomelandBuildTransactionJournal(descriptor: descriptor).read()) != nil
            message = "Purchase could not be fully confirmed. Use Check saved purchase; no automatic retry will be sent."
        }
    }
    func recoverPurchase(connection: HomelandGameConnectionStore) async {
        guard !busy, let descriptor = descriptor ?? importDescriptor else { return }
        busy = true; defer { busy = false }
        do {
            let journal = try HomelandBuildTransactionJournal(descriptor: descriptor)
            let record = try await connection.runBuildOperation { client, space in try await client.recoverBuildPurchase(journal, expectedSpaceID: space) }
            recovery = HomelandBuildRecoverySummary(record)
            purchasePhase = record.phase
            await refreshAfterOperation(connection: connection)
            message = record.phase == "complete" ? "Saved purchase verified. No new purchase was sent." : "Saved purchase still needs review; no new purchase was sent."
        } catch { message = "The saved operation cannot be reconciled in this session. No new purchase was sent." }
    }
    func checkPlacement(connection: HomelandGameConnectionStore) async {
        guard !busy, canImportArea, let plan = proposal else { return }
        busy = true; placementChecked = false; defer { busy = false }
        message = "Checking each position against current inventory, bounds and collisions…"
        do {
            if areaID>0 {try await connection.preparePurchaseConnection(currencyID:0,requirePlacementArea:areaID)}
            placementChecked = try await connection.runBuildOperation { client, space in try await client.checkBuildPlacement(plan, expectedSpaceID: space) }
            message = placementChecked ? "Every placement passed. Review the preview before importing." : "A position failed the game checks. Buy missing pieces if needed, or change the location."
        } catch { message = "Placement checks could not finish. Nothing was placed." }
    }
    func importBuild(connection: HomelandGameConnectionStore) async {
        guard !busy, canImportArea, placementChecked, !savedImport, let descriptor = importDescriptor, let plan = proposal, let processStart = connection.sessionProcessStart else { return }
        busy = true; placementChecked = false; defer { busy = false }
        message = "Importing once, then verifying newly created object IDs and positions…"
        do {
            let journal = try HomelandBuildImportJournal(descriptor: descriptor)
            let receipt = try await connection.runBuildOperation { client, space in
                try await client.importBuild(descriptor, plan: plan, expectedSpaceID: space, processStart: processStart, journal: journal)
            }
            try connection.trackImport(receipt)
            savedImport = true; importPhase = receipt.phase
            await refreshAfterOperation(connection: connection)
            message = "\(receipt.imported.count) new pieces verified. Previous placements are unchanged. Leave and return to test persistence."
        } catch {
            savedImport = (try? HomelandBuildImportJournal(descriptor: descriptor).read()) != nil
            message = "Import requires readback. Use Check saved import; no automatic retry will be sent."
        }
    }
    func selectWholeBuild(connection:HomelandGameConnectionStore) async {
        guard !busy,let descriptor=importDescriptor else{return}
        busy=true;defer{busy=false}
        do {
            let journal=try HomelandBuildImportJournal(descriptor:descriptor)
            guard let receipt=try journal.read(),receipt.phase=="verified" else{throw HomelandCommandClient.Failure.invalidRequest}
            try await connection.preparePurchaseConnection(currencyID:0,requireSelection:true)
            let count=try await connection.runBuildOperation{client,space in try await client.selectImportedBuild(receipt,expectedSpaceID:space)}
            message="\(count) pieces selected together in Aniimo. Choose Edit in the game to move the whole build."
        }catch{message="Open Residential Multi-Select in Aniimo and clear any unrelated selection, then try again. Missing pieces or changed item types will not be selected."}
    }
    func recoverImport(connection: HomelandGameConnectionStore) async {
        guard !busy, let descriptor = importDescriptor else { return }
        busy = true; defer { busy = false }
        do {
            let journal = try HomelandBuildImportJournal(descriptor: descriptor)
            let receipt = try await connection.runBuildOperation { client, space in try await client.recoverBuildImport(journal, expectedSpaceID: space) }
            try connection.trackImport(receipt)
            importPhase = receipt.phase
            await refreshAfterOperation(connection: connection)
            message = "Saved import verified; nothing was placed again."
        } catch { message = "The saved import still needs review. Nothing was placed again." }
    }
}
