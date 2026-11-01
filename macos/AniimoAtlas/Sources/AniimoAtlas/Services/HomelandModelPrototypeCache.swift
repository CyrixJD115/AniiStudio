import Foundation
import SceneKit

/// Shares decoded geometry/materials while cloning the editable node hierarchy.
actor HomelandModelPrototypeCache {
    static let shared = HomelandModelPrototypeCache()
    private let cache = NSCache<NSString, SCNNode>()
    private var pending: [String: Task<SCNNode, Error>] = [:]

    init() {
        cache.countLimit = 48
        cache.totalCostLimit = 128 * 1024 * 1024
    }

    func prototype(url: URL, prefab: String, load: @escaping @Sendable () async throws -> SCNNode) async throws -> SCNNode {
        try Task.checkCancellation()
        // URL resource values can retain cached metadata after a file is replaced.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(url.standardizedFileURL.path)#\(prefab)#\(size)#\(modified)"
        if let node = cache.object(forKey: key as NSString) { return node.clone() }
        let job: Task<SCNNode, Error>
        if let existing = pending[key] { job = existing }
        else {
            job = Task { try await load() }
            pending[key] = job
        }
        do {
            let node = try await job.value
            pending[key] = nil
            // Cost is an estimate; countLimit also bounds models with small files.
            let cost = min(max(1, size), 16 * 1024 * 1024) * 8
            cache.setObject(node, forKey: key as NSString, cost: cost)
            try Task.checkCancellation()
            return node.clone()
        } catch {
            pending[key] = nil
            throw error
        }
    }
}
