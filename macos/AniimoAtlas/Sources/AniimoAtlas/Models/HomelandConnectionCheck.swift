import Foundation

struct HomelandConnectionCheck {
    enum State { case ready, attention, pending }
    struct Row: Identifiable {
        let id: String
        let title: String
        let detail: String
        let state: State
    }
    let checkedAt: Date
    let validUntil: Date
    func isCurrent(at date: Date) -> Bool { date >= checkedAt && date <= validUntil }
    let rows: [Row]
    static func make(localReady: Bool, detail: String?, ownedHome: Bool,
                     resources: HomelandGameResources?, now: Date = Date()) -> Self {
        let homeReady = localReady && ownedHome
        let fresh = homeReady && resources.map { (0...30).contains(now.timeIntervalSince($0.checkedAt)) } == true
        let bud = resources?.balances.filter { $0.id == 1011 }
        let knownBud = bud?.count == 1 && bud?.first?.confirmedPositiveCount != nil
        let expiry = fresh && knownBud ? min(now.addingTimeInterval(30), resources!.checkedAt.addingTimeInterval(30)) : now.addingTimeInterval(30)
        return Self(checkedAt: now, validUntil: expiry, rows: [
            Row(id:"local",title:"Running game session",detail:detail ?? "The recorded game process and local listener match this session.",state:localReady ? .ready : .attention),
            Row(id:"home",title:"Your Homeland",detail:homeReady ? "Authenticated readback matches your owned Homeland." : "Connect to Aniimo and enter your own Homeland, then check again.",state:homeReady ? .ready : .pending),
            Row(id:"wallet",title:"Current wallet",detail:fresh && knownBud ? "Bud Ticket balance was read within 30 seconds. Each purchase still needs its own fresh quote." : "Refresh balances in the connected game. Cached or unverified counts cannot confirm affordability.",state:fresh && knownBud ? .ready : .pending),
            Row(id:"quote",title:"Purchase and import checks",detail:"For the selected build: check missing pieces, review the exact total, choose a location, then check it in the game. This connection check sends no purchase or placement.",state:.pending)
        ])
    }
}

enum HomelandTestBuildCandidates {
    static func select(_ builds: [HomelandBuild], server: HomelandServer = .americas, rv: Int = 16, limit: Int = 3) -> [HomelandBuild] {
        guard limit > 0 else { return [] }
        let eligible = builds.filter { build in
            guard build.server == server, build.number != 1549, build.kind == "Pixel Art", (build.rvLevel ?? Int.max) <= rv,
                  let pieces = build.pieceCount, (1...40).contains(pieces),
                  let costs = build.configuredCosts, let buds = costs["1011"], (1...80).contains(buds),
                  costs.allSatisfy({ $0.key == "1011" || $0.value == 0 }) else { return false }
            return true
        }
        var seen = Set<String>()
        return Array(eligible.sorted {
            let a = $0.configuredCosts!["1011"]!, b = $1.configuredCosts!["1011"]!
            return a == b ? $0.number < $1.number : a < b
        }.filter { seen.insert($0.id).inserted }.prefix(min(limit,10)))
    }
}
