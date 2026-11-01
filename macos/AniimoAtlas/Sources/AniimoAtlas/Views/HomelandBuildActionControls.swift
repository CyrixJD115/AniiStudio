import SwiftUI

struct HomelandBuildActionControls: View {
    let scene: HomelandLayoutScene
    let server: HomelandServer
    @ObservedObject var gameConnection: HomelandGameConnectionStore
    @State private var confirmPurchase = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                if server == .americas && scene.n == 1549 && scene.instanceCount == 14 {
                    GroupBox("Combo 1549 purchase test") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("6 Bright Pink + 8 Midnight Black · Maximum 28 Bud Tickets")
                            HStack {
                                Button("Check purchase") { Task { await gameConnection.checkCombo1549() } }
                                    .disabled(!gameConnection.connected || gameConnection.combo1549Busy)
                                Button("Purchase 14 blocks · 28 Bud Tickets") {
                                    Task { await gameConnection.purchaseCombo1549() }
                                }.disabled(!gameConnection.combo1549Ready || gameConnection.combo1549Busy)
                            }
                            HStack {
                                Button("Check import location") {
                                    Task { await gameConnection.prepareCombo1549Import(scene: scene) }
                                }.disabled(!gameConnection.connected || gameConnection.combo1549Busy)
                                Button("Import 14 blocks") { Task { await gameConnection.importCombo1549() } }
                                    .disabled(!gameConnection.combo1549ImportReady || gameConnection.combo1549Busy)
                            }
                            if let message = gameConnection.combo1549ImportMessage { Text(message).font(.caption) }
                            if gameConnection.combo1549Busy { ProgressView() }
                            if let message = gameConnection.combo1549Message { Text(message).font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if server == .americas && scene.n == 1361 && scene.instanceCount == 419 {
                    GroupBox("Import this build") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Buy all 419 blocks").font(.headline)
                                Spacer()
                                Button("Check in game") { Task { await gameConnection.readZeldaImportCheck() } }
                                    .disabled(!gameConnection.connected || gameConnection.isReadingResources || gameConnection.isMoving)
                            }
                            if let check = gameConnection.buildImportCheck {
                                if let total = check.configuredTotal { Text("Full configured price: \(total.formatted()) Bud Tickets") }
                                Text(check.plotsUnlocked == true ? "Target plots unlocked" : "Target plots still need checking")
                                if let level = check.homeLevel { Text("Current RV level: \(level)") }
                                if let maximum = check.totalGroupLimit { Text("Lemon Yellow group limit: \(maximum.formatted()) · remaining capacity still needs checking") }
                                Text("Checked \(check.checkedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                            if let error = gameConnection.buildImportError { Text(error).foregroundStyle(.orange) }
                            if HomelandZeldaPurchaseGrant.matchesScene(scene, server: server) {
                                HStack {
                                    Button("Purchase all 419 · 838 Bud Tickets") { confirmPurchase = true }
                                        .disabled(!gameConnection.purchasePilotStaged || !gameConnection.connected || gameConnection.isPurchasing || gameConnection.isReadingResources)
                                    if gameConnection.purchaseMessage != nil {
                                        Button("Check saved purchase") { Task { await gameConnection.checkZeldaPurchase() } }
                                            .disabled(!gameConnection.connected || gameConnection.isPurchasing || gameConnection.isReadingResources)
                                    }
                                }
                            }
                            if gameConnection.isPurchasing { ProgressView().controlSize(.small) }
                            if let message = gameConnection.purchaseMessage {
                                Text(message).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Purchase pilot awaiting activation. Placement remains a separate step.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
        }
        .confirmationDialog("Purchase 419 blocks for 838 Bud Tickets?", isPresented: $confirmPurchase, titleVisibility: .visible) {
            Button("Purchase blocks") { Task { await gameConnection.purchaseZelda(scene: scene, server: server) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}
