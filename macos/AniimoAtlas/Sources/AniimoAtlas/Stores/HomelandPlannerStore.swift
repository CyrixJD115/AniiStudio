import Combine
import Foundation
import SwiftUI

enum HomelandZone: String, CaseIterable, Identifiable {
    case rvInterior = "RV interior"
    case patio = "Patio & yard"
    case garden = "Garden"
    case aniimoYard = "Aniimo yard"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .rvInterior: return "caravan.fill"
        case .patio: return "sun.max.fill"
        case .garden: return "leaf.fill"
        case .aniimoYard: return "pawprint.fill"
        }
    }
}

enum HomelandMarker: String, CaseIterable, Identifiable {
    case room = "Room / cabin"
    case lounge = "Lounge"
    case garden = "Garden plot"
    case aniimo = "Aniimo nook"
    case workshop = "Workshop"
    case path = "Path"
    case light = "Light"
    case water = "Water feature"
    case decor = "Decor"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .room: return "house.fill"
        case .lounge: return "chair.lounge.fill"
        case .garden: return "carrot.fill"
        case .aniimo: return "pawprint.fill"
        case .workshop: return "hammer.fill"
        case .path: return "point.topleft.down.curvedto.point.bottomright.up"
        case .light: return "lamp.floor.fill"
        case .water: return "water.waves"
        case .decor: return "sparkles"
        }
    }
    var tint: Color {
        switch self {
        case .room: return .orange
        case .lounge: return .pink
        case .garden: return .green
        case .aniimo: return .purple
        case .workshop: return .brown
        case .path: return .yellow
        case .light: return .cyan
        case .water: return .blue
        case .decor: return .mint
        }
    }
}

@MainActor
final class HomelandPlannerStore: ObservableObject {
    @Published private(set) var placements: [String: String]
    @Published private(set) var completedGoals: Set<String>

    private let defaults: UserDefaults
    private let storageKey = "homeland.planner.v1"

    private struct SavedPlan: Codable {
        var placements: [String: String]
        var completedGoals: [String]
    }

    static let goals: [(id: String, title: String)] = [
        ("rv", "Plan an RV interior that feels like home"),
        ("yard", "Lay out the patio and yard"),
        ("garden", "Reserve a clear space for crops"),
        ("aniimo", "Make room for Home Aniimo"),
        ("work", "Group work areas for quick visits"),
        ("orders", "Leave a spot for orders and supplies"),
        ("furniture", "Add a focal point or interactive furniture")
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(SavedPlan.self, from: data) {
            placements = saved.placements
            completedGoals = Set(saved.completedGoals)
        } else {
            placements = [:]
            completedGoals = []
        }
    }

    func marker(at index: Int, in zone: HomelandZone) -> HomelandMarker? {
        guard let raw = placements[key(zone, index)], let marker = HomelandMarker(rawValue: raw) else { return nil }
        return marker
    }

    func place(_ marker: HomelandMarker?, at index: Int, in zone: HomelandZone) {
        let id = key(zone, index)
        if let marker { placements[id] = marker.rawValue } else { placements.removeValue(forKey: id) }
        save()
    }

    func clear(_ zone: HomelandZone) {
        let prefix = zone.rawValue + ":"
        placements = placements.filter { !$0.key.hasPrefix(prefix) }
        save()
    }

    func count(in zone: HomelandZone) -> Int {
        let prefix = zone.rawValue + ":"
        return placements.keys.filter { $0.hasPrefix(prefix) }.count
    }

    func toggleGoal(_ id: String) {
        if completedGoals.contains(id) { completedGoals.remove(id) } else { completedGoals.insert(id) }
        save()
    }

    private func key(_ zone: HomelandZone, _ index: Int) -> String { "\(zone.rawValue):\(index)" }

    private func save() {
        let state = SavedPlan(placements: placements, completedGoals: Array(completedGoals))
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: storageKey) }
    }
}
