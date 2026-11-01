import SwiftUI

struct HomelandConnectionCheckView: View {
    @ObservedObject var connection: HomelandGameConnectionStore
    @StateObject private var catalog = HomelandBuildStore()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Connection check", systemImage: "checkmark.shield").font(.title2.bold())
                    Text("Check the game session before reviewing a purchase or import.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button("Run read-only check", systemImage: "arrow.clockwise") { Task { await connection.checkConnectionReadiness() } }
                            .buttonStyle(.borderedProminent).disabled(busy)
                        if !connection.connected {
                            Button("Connect to game") { Task { await connection.connect(); await connection.checkConnectionReadiness() } }
                                .disabled(busy || connection.status == .connecting)
                        }
                        Spacer()
                        if connection.isCheckingReturn { ProgressView().controlSize(.small) }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let report = connection.connectionCheck {
                            let current = report.isCurrent(at: context.date)
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Checked \(report.checkedAt.formatted(date: .omitted,time: .shortened))\(current ? "" : " · refresh this check")")
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(report.rows) { row in
                                    HStack(alignment: .top,spacing: 12) {
                                        Image(systemName: row.state == .ready && current ? "checkmark.circle.fill" : "circle.dashed")
                                            .foregroundStyle(row.state == .ready && current ? Color.green : .secondary)
                                        VStack(alignment: .leading,spacing: 4) {
                                            Text(row.title).font(.headline)
                                            Text(row.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                                        }
                                    }
                                }
                            }.padding(18).atlasGlass(cornerRadius:18)
                        } else {
                            Text("No current check yet. This panel does not start Aniimo or activate its game bridge.")
                                .foregroundStyle(.secondary).padding(18).frame(maxWidth:.infinity,alignment:.leading).atlasGlass(cornerRadius:18)
                        }
                    }
                    checklist
                    candidates
                }.padding(24)
            }
        }.frame(width: 820,height: 740).background { StudioBackdrop() }
    }
    private var busy: Bool { connection.status == .connecting || connection.isCheckingReturn || connection.isPurchasing || connection.isReadingResources || connection.isMoving }
    private var checklist: some View {
        VStack(alignment:.leading,spacing:10) {
            Label("When you're ready to test",systemImage:"list.bullet.clipboard").font(.headline)
            Text("1. Enter your own Homeland and refresh the connection and wallet.")
            Text("2. Open a small build, check missing pieces, and review the exact cost before approving a budget.")
            Text("3. Review the position preview and game location checks, then import once.")
            Text("4. Check Activity readback, leave and return, then restart Aniimo to test persistence.")
            Divider()
            Text("If interrupted: check the saved purchase/import in Activity. Do not buy or import again, clear receipts, or remove unverified objects.")
                .foregroundStyle(.secondary)
            Text("Rollback: drafts and app backups preserve local work. Returning furniture requires verified instance IDs and a separately reviewed game action; an app backup does not undo a server purchase.")
                .font(.caption).foregroundStyle(.secondary)
        }.font(.callout).padding(18).atlasGlass(cornerRadius:18)
    }
    private var candidates: some View {
        VStack(alignment:.leading,spacing:12) {
            Label("Small test candidates · Americas",systemImage:"cube.box").font(.headline)
            Text("Cached full-design estimates—not live quotes or confirmed affordability. Search the build number in Build Library. Nothing is purchased from this list.")
                .font(.caption).foregroundStyle(.secondary)
            let builds = HomelandTestBuildCandidates.select(catalog.builds)
            ForEach(builds) { build in
                HStack {
                    VStack(alignment:.leading,spacing:3) {
                        Text("#\(build.number) · \(build.designer)").font(.callout.bold())
                        Text("\(build.pieceCount ?? 0) pieces · RV\(build.rvLevel ?? 0)+").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HomelandCurrencyAmount(id:1011,name:"Full design estimate",amount:(build.configuredCosts?["1011"] ?? 0).formatted())
                }
            }
            if builds.isEmpty { Text("Sync the Americas catalog in Build Library to populate this shortlist.").font(.caption).foregroundStyle(.secondary) }
        }.padding(18).atlasGlass(cornerRadius:18)
    }
}
