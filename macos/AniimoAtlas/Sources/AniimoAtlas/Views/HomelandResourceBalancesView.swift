import SwiftUI

struct HomelandResourceBalancesView: View {
    @State private var showingConnectionCheck = false
    @AppStorage("atlas.autoConnectHomeland") private var autoConnect = true
    @ObservedObject var connection: HomelandGameConnectionStore
    var showsConnectionControls = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { balances; Spacer(minLength: 8); if showsConnectionControls { refresh } }
                VStack(alignment: .leading, spacing: 10) { balances; if showsConnectionControls { refresh } }
            }
            HStack {
                if let snapshot = connection.resources {
                HStack(spacing: 5) {
                    Circle().fill(connection.connected ? .green : .orange).frame(width: 5, height: 5)
                    Text(connection.connected ? "Updated \(snapshot.checkedAt.formatted(date: .omitted, time: .shortened))" : "Disconnected · saved balances")
                }.font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if showsConnectionControls { Toggle("Auto-connect", isOn: $autoConnect).toggleStyle(.checkbox).font(.caption2) }
            }
            if let message = connection.connectionMessage { Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if let error = connection.resourceError { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }
        .sheet(isPresented: $showingConnectionCheck) { HomelandConnectionCheckView(connection: connection) }
    }
    private var balances: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { currencyEntries }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 14) { currencyEntries }
        }
    }
    @ViewBuilder private var currencyEntries: some View {
        ForEach([Int64(1), 2, 1010, 1011], id: \.self) { id in
            let balance = connection.resources?.balances.first { $0.id == id }
            HomelandCurrencyAmount(id: id, name: balance?.name ?? currencyName(id),
                amount: balance?.confirmedPositiveCount?.formatted() ?? "—")
                .help(balance == nil ? "Connect to Aniimo to read this balance" : "\(balance!.name) balance")
        }
    }
    private func currencyName(_ id: Int64) -> String {
        switch id {
        case 1: return "Glimmer"
        case 2: return "Credits"
        case 1010: return "Home Coin"
        default: return "Bud Ticket"
        }
    }
    private var refresh: some View {
        HStack(spacing: 8) {
            Button("Connection check", systemImage: "checkmark.shield") { showingConnectionCheck = true }
            if !connection.connected {
                Button("Connect to game") { Task { await connection.connect() } }
                    .disabled(connection.status == .connecting)
            }
            Button { Task { await connection.refreshResources() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }.disabled(!connection.connected || connection.isReadingResources || connection.isMoving || connection.isCheckingReturn || connection.isPurchasing)
        }.controlSize(.small)
    }
}
