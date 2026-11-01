import Foundation
struct InstalledWorkerData: Decodable {
    let build: String
    let jobs: [HomelandWorkerJob]
    let workers: [HomelandWorkerProfile]
    static let current: Self = {
        guard let url = Bundle.module.url(forResource: "installed-worker-data", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(build: "", jobs: [], workers: [])
        }
        return value
    }()
    func workers(for job: String) -> [HomelandWorkerProfile] {
        workers.filter { $0.abilities[job] != nil }.sorted {
            let a = $0.abilities[job, default: 0], b = $1.abilities[job, default: 0]
            return a == b ? ($0.name, $0.formName, $0.formID) < ($1.name, $1.formName, $1.formID) : a > b
        }
    }
}
struct HomelandWorkerJob: Decodable, Identifiable {
    let id, name, facilityKey, description: String
}
struct HomelandWorkerProfile: Decodable, Identifiable {
    let formID, speciesID, name, formName: String
    let abilities: [String: Int]
    let isNew: Bool
    var id: String { formID }
}
