import SwiftUI

private struct GuideBlock: Identifiable {
    let title: String
    let copy: String
    let points: [String]
    var id: String { title }
}

private struct GuideTask: Identifiable {
    let id: String
    let title: String
    let detail: String
}

private struct FieldGuide: Identifiable {
    let id: String
    let title: String
    let category: String
    let symbol: String
    let summary: String
    let blocks: [GuideBlock]
    let weeklyTasks: [GuideTask]
    let longTermTasks: [GuideTask]
    let sources: [(String, String)]

    var tint: Color {
        switch category {
        case "Battle": return .orange
        case "Collection": return .purple
        case "Endgame": return .teal
        default: return .green
        }
    }
}

struct GameGuidesView: View {
    let onOpenAniilog: () -> Void

    @State private var selectedID = "egg-heist"
    @State private var search = ""
    @State private var category = "All guides"
    @AppStorage("fieldGuides.completedTasks") private var completedTaskData = "[]"

    private let categories = ["All guides", "Battle", "Collection", "Endgame", "Resources"]
    private var guides: [FieldGuide] { Self.guidesData }
    private var visibleGuides: [FieldGuide] {
        guides.filter { guide in
            (category == "All guides" || guide.category == category) &&
            (search.isEmpty || guide.title.localizedCaseInsensitiveContains(search) || guide.summary.localizedCaseInsensitiveContains(search))
        }
    }
    private var selectedGuide: FieldGuide { visibleGuides.first(where: { $0.id == selectedID }) ?? visibleGuides.first ?? guides[0] }
    private var completedTasks: Set<String> {
        guard let data = completedTaskData.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values)
    }
    private var currentWeekToken: String {
        let calendar = Calendar(identifier: .iso8601)
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(parts.yearForWeekOfYear ?? 0)-W\(parts.weekOfYear ?? 0)"
    }

    var body: some View {
        HSplitView {
            guideIndex
                .frame(minWidth: 235, idealWidth: 285, maxWidth: 340)
            articlePane
                .frame(minWidth: 440, idealWidth: 760)
        }
        .onChange(of: category) { _, _ in selectFirstVisible() }
        .onChange(of: search) { _, _ in selectFirstVisible() }
        .onAppear { selectFirstVisible() }
    }

    private var guideIndex: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                Text("FIELD GUIDES")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.teal)
                Text("Play smarter")
                    .font(.title2.bold())
            }
            TextField("Search guides", text: $search)
                .textFieldStyle(.roundedBorder)
            Picker("Guide category", selection: $category) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(visibleGuides) { guide in
                        Button { selectedID = guide.id } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: guide.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(guide.tint)
                                    .frame(width: 30, height: 30)
                                    .background(guide.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(guide.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text(guide.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedID == guide.id ? guide.tint.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    if visibleGuides.isEmpty {
                        ContentUnavailableView("No matching guides", systemImage: "magnifyingglass", description: Text("Try another search or category."))
                    }
                }
            }
        }
        .padding(18)
    }

    private var articlePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                articleHeader
                if selectedGuide.id == "forms-and-styles" {
                    catalogSnapshot
                }
                ForEach(selectedGuide.blocks) { block in
                    GuideBlockView(block: block, tint: selectedGuide.tint)
                }
                if !selectedGuide.weeklyTasks.isEmpty || !selectedGuide.longTermTasks.isEmpty {
                    endgameChecklist
                }
                if selectedGuide.id == "forms-and-styles" {
                    Button(action: onOpenAniilog) {
                        Label("Browse forms and appearances in the Aniilog", systemImage: "square.grid.2x2.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                sourcesPane
                Text("Originally written for Aniimo Atlas. Strategy tips are guidance, not guarantees; combat balance, event schedules, and rewards can change between updates.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(selectedGuide.category, systemImage: selectedGuide.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedGuide.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selectedGuide.tint.opacity(0.12), in: Capsule())
                Text("Reviewed Sep 23, 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(selectedGuide.title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(selectedGuide.summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var catalogSnapshot: some View {
        let forms = Creature.all.reduce(0) { $0 + $1.forms.count }
        let looks = Creature.all.reduce(0) { $0 + $1.appearanceCount }
        let formNames = Array(Set(Creature.all.flatMap(\.forms).map(\.name))).sorted()
        let appearanceOrder = ["Standard", "Sparkling I", "Sparkling II", "Sparkling III", "Sparkling IV", "Sparkling V", "Sparkling VI", "Sparkling VII", "Sparkling VIII", "Sparkling IX", "Sparkling X", "Dazzling Sparkling", "Shadow Sparkling", "Umbral"]
        let appearanceSet = Set(Creature.all.flatMap(\.forms).flatMap(\.appearances).map(\.name))
        let appearanceNames = appearanceOrder.filter(appearanceSet.contains) + appearanceSet.subtracting(appearanceOrder).sorted()
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                snapshotValue("Aniimo", value: Creature.all.count.formatted())
                Divider().frame(height: 42)
                snapshotValue("Forms", value: forms.formatted())
                Divider().frame(height: 42)
                snapshotValue("Rendered looks", value: looks.formatted())
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Text("FORM NAMES IN THE CATALOG")
                    .font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
                tagGrid(formNames, tint: .teal)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("APPEARANCE STYLES IN THE CATALOG")
                    .font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
                tagGrid(appearanceNames, tint: .purple)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tagGrid(_ values: [String], tint: Color) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 7) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.1), in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func snapshotValue(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var endgameChecklist: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Endgame taskboard", systemImage: "checklist")
                .font(.title2.bold())
            if !selectedGuide.weeklyTasks.isEmpty {
                taskGroup("Weekly reset", tasks: selectedGuide.weeklyTasks, resetsWeekly: true)
            }
            if !selectedGuide.longTermTasks.isEmpty {
                taskGroup("Long-term goals", tasks: selectedGuide.longTermTasks)
            }
            Text("Checkmarks are a personal Atlas checklist; they do not read your game save.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func taskGroup(_ title: String, tasks: [GuideTask], resetsWeekly: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            ForEach(tasks) { task in
                let storageID = resetsWeekly ? "\(currentWeekToken):\(task.id)" : task.id
                let complete = completedTasks.contains(storageID)
                Button { toggleTask(storageID) } label: {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(complete ? Color.green : Color.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                            Text(task.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourcesPane: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Official references").font(.headline)
            ForEach(Array(selectedGuide.sources.enumerated()), id: \.offset) { _, source in
                if let url = URL(string: source.1) {
                    Link(destination: url) { Label(source.0, systemImage: "arrow.up.right") }
                        .font(.callout)
                }
            }
        }
        .padding(.top, 4)
    }

    private func toggleTask(_ id: String) {
        var values = completedTasks
        if values.contains(id) { values.remove(id) } else { values.insert(id) }
        let data = (try? JSONEncoder().encode(values.sorted())) ?? Data("[]".utf8)
        completedTaskData = String(decoding: data, as: UTF8.self)
    }

    private func selectFirstVisible() {
        if !visibleGuides.contains(where: { $0.id == selectedID }) {
            selectedID = visibleGuides.first?.id ?? "egg-heist"
        }
    }

    private static let guidesData: [FieldGuide] = [
        FieldGuide(
            id: "egg-heist",
            title: "Operation: Egg Heist",
            category: "Battle",
            symbol: "shippingbox.fill",
            summary: "A PvPvE extraction run: loot Lost Isles, meet a personal objective, then get out with your haul.",
            blocks: [
                GuideBlock(title: "Win condition: leave with something banked", copy: "Egg Heist rewards a clean extraction. The official February rules allow evacuation after either personally submitting one Aniimo Egg or collecting the required amount of Eggshell Coins. The game lowers that coin threshold in the same update; check the in-mode objective for the exact current amount.", points: ["Choose your personal exit condition before you chase a second objective.", "Once it is met, head for evacuation. Extra looting only pays if you survive the run."]),
                GuideBlock(title: "Solo route: gather first, contest by choice", copy: "The official mode overview allows solo exploration and supply gathering, as well as fights against other teams for the Giant Darkler Egg. You do not have to turn every encounter into a fight.", points: ["If the central contest is crowded, favor supplies and the coin objective, then leave as soon as you qualify.", "Keep enough time to reach the exit; a bag full of loot is worth nothing if you miss evacuation."]),
                GuideBlock(title: "Team route: make the exit a team decision", copy: "Submitted Aniimo Eggs are shared with teammates only after a successful evacuation. If the team fails to evacuate, each Pathfinder keeps only the eggs they personally submitted.", points: ["Agree on a call to leave before the run starts.", "Do not assume a teammate's egg alone completes your personal evacuation requirement.", "When one player has met their own objective, regroup and extract rather than splitting for one more pickup."]),
                GuideBlock(title: "Chaos Mode: high stakes, higher-value drops", copy: "The September 2026 update adds Chaos Mode for Team Mode. It requires Tier IV Elite Egg Seeker and a Chaos Ticket; the notice calls out higher Prismana Egg and Prismatic Collectible rates, rare Secret Collectibles, and strict escape rules. The team is explicitly recommended.", points: ["Build a reliable ordinary extraction routine before spending a ticket.", "Queue with a group that agrees on objectives and an exit call.", "Check the in-game mode screen for current region unlock time and entry rules."])
            ],
            weeklyTasks: [], longTermTasks: [],
            sources: [
                ("Egg Heist mode overview · Jan 29 update", "https://aniimo.com/newslist/detail/100013"),
                ("Team egg sharing and evacuation rules · Feb 4 update", "https://www.aniimo.com/newslist/detail/100019"),
                ("Chaos Mode unlock and entry rules · Sep 23 update", "https://aniimo.com/newslist/detail/100145")
            ]
        ),
        FieldGuide(
            id: "forms-and-styles",
            title: "Forms, Sparkling styles & rare variants",
            category: "Collection",
            symbol: "sparkles",
            summary: "Keep species, ecological forms, and appearance styles separate so you know what you have—and what the catalog actually supports.",
            blocks: [
                GuideBlock(title: "Three layers, three different things", copy: "An Aniimo’s species is its Aniilog entry. A form is a distinct form of that species, often tied to a habitat, weather, time, or special trait. An appearance is a visual style applied to a form. Atlas keeps forms separate from appearance styles and only lists combinations present in its sources.", points: ["Form examples in this catalog include Bay, Beach, Cloudmist, Grassland, Highland, Rainstorm, Snowfield, Thunderstorm, Towerwood, and Prismana.", "Standard, Sparkling I–X, Dazzling Sparkling, Shadow Sparkling, and Umbral are appearance/style labels—not extra species.", "Not every form has every style. The Aniilog’s form picker and the appearance list show the supported combinations."]),
                GuideBlock(title: "Sparkling styles and cube odds", copy: "The official probability page distinguishes the regular Sparkling style from Dazzling and Shadow. With a Sparkling Cube, the published split is 99% common Sparkling and 1% Dazzling for wild captures and ordinary eggs. Egg Heist eggs instead list 99% common Sparkling and 1% Shadow. Sigils and Pigment list 99% common, 0.5% Dazzling, and 0.5% Shadow.", points: ["The September update says an Aniimo caught with a Sparkling Cube now has guaranteed Perfect Potential.", "Use the matching egg source when you are chasing a specific rare style; the Egg Heist table differs from ordinary eggs.", "Odds describe style outcomes, not the chance of finding a particular species or egg."]),
                GuideBlock(title: "Prismana and Umbral are separate pursuits", copy: "Prismana is listed as a form, not as a Sparkling tier. Official update notes describe Prismana Flow from ecosystem nurturing and say lucky strikes can add Prismatic Energy or trigger a flow. Umbral Aniimo are described as appearing through nurtured Wild Surges and sometimes in the open world; they have Perfect Potential.", points: ["Treat the target form and the target appearance as separate checklist goals.", "A Sparkling Cube, a Prismana form, and an Umbral appearance are not interchangeable terms.", "Open the Aniilog entry to see whether a specific form/style render is available in Atlas."])
            ],
            weeklyTasks: [], longTermTasks: [],
            sources: [
                ("Official Sparkling and catch probability details", "https://www.aniimo.com/formula-multipliers"),
                ("Developer update: Prismana, Umbral, training and Home changes", "https://aniimo.com/newslist/detail/100064")
            ]
        ),
        FieldGuide(
            id: "endgame",
            title: "Endgame & weekly taskboard",
            category: "Endgame",
            symbol: "flag.checkered",
            summary: "A reset-aware plan for Holo-Battle Interlink, seasonal activities, Egg Heist progression, and long-term completion goals.",
            blocks: [
                GuideBlock(title: "Start with the weekly window", copy: "Holo-Battle Interlink unlocks at Trailblazer I and runs Thursday 04:00 through Monday 03:59 (UTC+8) according to the current official notice. It has three routes with different Alpha encounters and environmental mechanics. You can replay routes; Atlas’s checklist below helps you remember the reset-sensitive rewards. Check your in-game event panel for the schedule on your server.", points: ["Set a team lineup and choose buffs before each route; in four-player co-op, the team leader selects the buffs.", "Each route tracks its best Star Rank independently. Raise the weakest route to improve the combined total.", "Helping another Pathfinder improve their Star Rank can earn Support Rewards. Star and Support rewards reset weekly."]),
                GuideBlock(title: "Push Egg Heist rank before the next tier", copy: "The September update sets Chaos Mode behind Tier IV Elite Egg Seeker and a Chaos Ticket. Chaos offers better chances at Prismana Eggs and Prismatic Collectibles, but escape rules are stricter and the team is recommended.", points: ["Practice clean evacuations in the lower difficulties; a successful run protects your haul and builds rank.", "Save a ticket for a team with a clear objective and a practiced exit call."]),
                GuideBlock(title: "Use timed events before their free attempts expire", copy: "The current official notice says Aniimo Discovery free Search Attempts replenish but do not stack. Vein Abundance rotates between named regions, and Holo-Battle Interlink has a weekly schedule. Event windows and unlock requirements change, so use the event screen as the final authority.", points: ["Spend non-stacking free attempts while an event is active.", "Check regional schedules before planning a Prismana hunt.", "Claim reward milestones before the activity resets or closes."])
            ],
            weeklyTasks: [
                GuideTask(id: "weekly-holo-routes", title: "Set a best Star Rank on all three Holo routes", detail: "Replay the route with the weakest score before the weekly reset."),
                GuideTask(id: "weekly-holo-support", title: "Claim Star and Support Rewards", detail: "Help a teammate improve a route, then claim both reward tracks."),
                GuideTask(id: "weekly-event-attempts", title: "Use free event attempts", detail: "When Aniimo Discovery is active, free Search Attempts do not stack."),
                GuideTask(id: "weekly-vein-window", title: "Check the Vein Abundance region", detail: "Visit the scheduled region while the limited window is open.")
            ],
            longTermTasks: [
                GuideTask(id: "goal-level-60", title: "Reach Pathfinder level 60", detail: "A Steam achievement tracks Institute Senior."),
                GuideTask(id: "goal-sanctums", title: "Complete 10 Sanctums", detail: "Build a balanced team for the Sanctum Savant milestone."),
                GuideTask(id: "goal-chests", title: "Find the 200 world chests", detail: "A map route makes this exploration goal easier to finish."),
                GuideTask(id: "goal-holo-stars", title: "Earn 50 Holo-Battle stars", detail: "Stars accumulate across the Interlink routes."),
                GuideTask(id: "goal-home-orders", title: "Fulfill 80 Home orders", detail: "Make this part of the regular Homeland loop."),
                GuideTask(id: "goal-region-aniilog", title: "Raise a regional Aniilog to level 9", detail: "The Breezy Plains has a named completion achievement."),
                GuideTask(id: "goal-challenges", title: "Complete 50 Pathfinder Challenges", detail: "Clear available challenges as you progress through Idyll.")
            ],
            sources: [
                ("Weekly Holo-Battle and current events · Sep 23 update", "https://aniimo.com/newslist/detail/100145"),
                ("Official Steam achievements", "https://steamcommunity.com/stats/4126040/achievements")
            ]
        ),
        FieldGuide(
            id: "resource-loops",
            title: "Easy resource loops",
            category: "Resources",
            symbol: "leaf.fill",
            summary: "Spend your playtime on the activity that pays the resource you need instead of repeating one route for everything.",
            blocks: [
                GuideBlock(title: "For fast captures: high-density zones + Tumblers", copy: "The official January notice raised the Tumbler base capture multiplier to 6× in high-density areas. Tumblers do not use the normal back-attack bonus, so prioritize a dense spawn cluster and clear inventory space first.", points: ["Keep at least 10 free Aniimo backpack slots before using a Tumbler, as the official notice recommends.", "Use the in-game density and capture rules; the 6× bonus is specifically called out for high-density areas.", "For a wild Surge target, the official probability page lists a separate Tumbler multiplier."]),
                GuideBlock(title: "For steady growth: let Homeland do its cycles", copy: "Homeland supports crops and Aniimo dispatch trips, and official updates confirm offline crop harvesting and Home orders. The developer update expands the Home into multiple areas with house building and furniture.", points: ["Collect ripe crops and completed dispatch rewards when you visit the Home.", "Fill available Home orders with items you already produce; avoid spending scarce materials just to clear a low-value order.", "Place work and planting areas where they are easy to revisit in your layout plan."]),
                GuideBlock(title: "For weekly rewards: Holo-Battle Interlink", copy: "Interlink has three replayable routes, combined Star milestones, and Support Rewards. Both reward tracks reset weekly, making it a reliable scheduled stop once Trailblazer I is unlocked.", points: ["Do one pass through all three routes, then replay the route with the weakest Star Rank.", "If a route is a wall, help another group for Support Rewards and return with a better team or buff plan."]),
                GuideBlock(title: "For XP and training: check the Outpost first", copy: "The official January update halved the Outpost Shop price of Experience Gems and raised the Experience Gem refund when releasing an Aniimo to 80%. Shop contents and prices can change, so verify them in-game before farming.", points: ["Use Experience Gems on your current team before grinding low-yield encounters.", "Releasing duplicates returns most—but not all—of the Experience Gems; release only Aniimo you are sure you do not want.", "The September developer update says Sparkling Cube captures guarantee Perfect Potential, useful when a capture also advances a training goal."]),
                GuideBlock(title: "For Prismana: combine nurturing and current events", copy: "Ecosystem nurturing advances Prismatic Energy, while lucky strikes can add energy and may trigger Prismana Flow. The current official schedule also includes rotating Vein Abundance regions and Search events.", points: ["Work on the target species or region while you build energy; the developer notes make nurturing part of normal exploration.", "Spend free event attempts before they expire, since the current notice says they do not stack.", "Use the live event calendar for exact region, schedule, and reward details."])
            ],
            weeklyTasks: [], longTermTasks: [],
            sources: [
                ("Capture multiplier, Tumbler and Outpost changes · Jan 29", "https://aniimo.com/newslist/detail/100013"),
                ("Catch and Sparkling probability details", "https://www.aniimo.com/formula-multipliers"),
                ("Homeland, nurturing and training changes", "https://aniimo.com/newslist/detail/100064"),
                ("Current weekly events and region rotation", "https://aniimo.com/newslist/detail/100145")
            ]
        )
    ]
}

private struct GuideBlockView: View {
    let block: GuideBlock
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(block.title).font(.title2.bold())
            Text(block.copy)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(block.points.enumerated()), id: \.offset) { index, point in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.top, 3)
                    Text(point).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
