import Foundation

struct HomelandSceneTransform: Codable, Equatable {
    var positionX: Double
    var positionY: Double
    var positionZ: Double
    var rotationX: Double
    var rotationY: Double
    var rotationZ: Double
    var scaleX: Double
    var scaleY: Double
    var scaleZ: Double

    var isValidPreview: Bool {
        [positionX, positionY, positionZ, rotationX, rotationY, rotationZ, scaleX, scaleY, scaleZ]
            .allSatisfy(\.isFinite) && [scaleX, scaleY, scaleZ].allSatisfy { $0 > 0 && $0 <= 100 }
    }
}

struct HomelandSceneSelection: Identifiable, Equatable {
    let id: String
    let prefab: String
    let ordinal: Int
    let transform: HomelandSceneTransform
}

struct HomelandTransformDraft: Equatable {
    var transform: HomelandSceneTransform

    init(transform: HomelandSceneTransform) { self.transform = transform }

    init(selection: HomelandSceneSelection) {
        transform = selection.transform
    }
}
