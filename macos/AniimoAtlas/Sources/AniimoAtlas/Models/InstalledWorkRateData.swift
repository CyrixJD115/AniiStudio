import Foundation
struct InstalledWorkRateData: Decodable {
    let attackByWorkerLevel, defenseByRequiredLevel: [String: Double]
    let guideBindings: [String: WorkRateBinding]
    static let current: Self = {
        guard let url = Bundle.module.url(forResource: "installed-work-rate-data", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self(attackByWorkerLevel: [:], defenseByRequiredLevel: [:], guideBindings: [:]) }
        return value
    }()
    // Reviewed 3013/3054 arithmetic only. No game formula is executed.
    // Ideal fed worker; environment, power and runtime allocation are separate.
    func unitsPerMinute(recipeID: String, workerLevel: Int, personality: Bool) -> Double? {
        guard let binding = guideBindings[recipeID], (1...4).contains(workerLevel), (1...4).contains(binding.requiredLevel), workerLevel >= binding.requiredLevel else { return nil }
        let required = binding.requiredLevel
        let rate: Double
        switch binding.functionID {
        case 3013:
            guard let attack = attackByWorkerLevel[String(workerLevel)], let defense = defenseByRequiredLevel[String(required)] else { return nil }
            rate = attack - defense
        case 3054:
            rate = 60 * (required >= workerLevel ? 1 + 0.25 * Double(workerLevel - required) : 2 + Double(workerLevel - required))
        default: return nil
        }
        let result = rate * (personality ? 1.2 : 1)
        return result.isFinite && result > 0 ? result : nil
    }
}
struct WorkRateBinding: Decodable {
    let formulaID, operationID: String
    let functionID, requiredLevel: Int
}
