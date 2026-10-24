import Foundation

struct HomelandVector3<Value: Equatable>: Equatable {
    let x: Value
    let y: Value
    let z: Value
}

struct HomelandOrnamentRecord: Equatable {
    enum DecodeError: Error, Equatable {
        case invalidBase64
        case tooShort(Int)
        case unsupportedFlags(UInt16)
        case conflictingScaleFlags
        case wrongSize(expected: Int, actual: Int)
    }

    static let positionUnits = 100.0
    static let rotationUnits = 100.0
    static let scaleUnits = 1_000.0

    let flags: UInt16
    let homeID: UInt32
    let rawPosition: HomelandVector3<Int>
    let rawRotation: HomelandVector3<Int>
    let rawScale: HomelandVector3<Int>
    let trashID: UInt16
    let areaID: UInt8
    let electricMode: Bool

    var position: HomelandVector3<Double> {
        HomelandVector3(
            x: Double(rawPosition.x) / Self.positionUnits,
            y: Double(rawPosition.y) / Self.positionUnits,
            z: Double(rawPosition.z) / Self.positionUnits
        )
    }

    var rotationDegrees: HomelandVector3<Double> {
        HomelandVector3(
            x: Double(rawRotation.x) / Self.rotationUnits,
            y: Double(rawRotation.y) / Self.rotationUnits,
            z: Double(rawRotation.z) / Self.rotationUnits
        )
    }

    var scale: HomelandVector3<Double> {
        HomelandVector3(
            x: Double(rawScale.x) / Self.scaleUnits,
            y: Double(rawScale.y) / Self.scaleUnits,
            z: Double(rawScale.z) / Self.scaleUnits
        )
    }

    static func decode(base64: String) throws -> HomelandOrnamentRecord {
        guard let data = Data(base64Encoded: base64) else {
            throw DecodeError.invalidBase64
        }
        return try decode(bytes: [UInt8](data))
    }

    static func decode(bytes: [UInt8]) throws -> HomelandOrnamentRecord {
        let fixedBytes = 12
        guard bytes.count >= fixedBytes else {
            throw DecodeError.tooShort(bytes.count)
        }

        let hasYaw: UInt16 = 0x0001
        let hasPitchRoll: UInt16 = 0x0002
        let uniformScale: UInt16 = 0x0004
        let xyzScale: UInt16 = 0x0008
        let hasTrash: UInt16 = 0x0010
        let electric: UInt16 = 0x0020
        let areaMask: UInt16 = 0x000f
        let areaShift: UInt16 = 6
        let extendedArea: UInt16 = 0x0400
        let knownFlags = hasYaw | hasPitchRoll | uniformScale | xyzScale | hasTrash
            | electric | (areaMask << areaShift) | extendedArea

        let flags = readUInt16(bytes, 0)
        let unsupported = flags & ~knownFlags
        guard unsupported == 0 else {
            throw DecodeError.unsupportedFlags(unsupported)
        }
        guard flags & uniformScale == 0 || flags & xyzScale == 0 else {
            throw DecodeError.conflictingScaleFlags
        }

        var expected = fixedBytes
        if flags & hasYaw != 0 { expected += 2 }
        if flags & hasPitchRoll != 0 { expected += 4 }
        if flags & uniformScale != 0 { expected += 2 }
        else if flags & xyzScale != 0 { expected += 6 }
        if flags & hasTrash != 0 { expected += 2 }
        if flags & extendedArea != 0 { expected += 1 }
        guard bytes.count == expected else {
            throw DecodeError.wrongSize(expected: expected, actual: bytes.count)
        }

        var cursor = fixedBytes
        var rotation = HomelandVector3(x: 0, y: 0, z: 0)
        if flags & hasYaw != 0 {
            rotation = HomelandVector3(x: rotation.x, y: Int(readUInt16(bytes, cursor)), z: rotation.z)
            cursor += 2
        }
        if flags & hasPitchRoll != 0 {
            rotation = HomelandVector3(
                x: Int(readUInt16(bytes, cursor)),
                y: rotation.y,
                z: Int(readUInt16(bytes, cursor + 2))
            )
            cursor += 4
        }

        var scale = HomelandVector3(x: 1_000, y: 1_000, z: 1_000)
        if flags & uniformScale != 0 {
            let value = Int(readUInt16(bytes, cursor))
            scale = HomelandVector3(x: value, y: value, z: value)
            cursor += 2
        } else if flags & xyzScale != 0 {
            scale = HomelandVector3(
                x: Int(readUInt16(bytes, cursor)),
                y: Int(readUInt16(bytes, cursor + 2)),
                z: Int(readUInt16(bytes, cursor + 4))
            )
            cursor += 6
        }

        let trashID: UInt16
        if flags & hasTrash != 0 {
            trashID = readUInt16(bytes, cursor)
            cursor += 2
        } else {
            trashID = 0
        }
        let inlineArea = UInt8((flags >> areaShift) & areaMask)
        let areaID = flags & extendedArea != 0 ? bytes[cursor] : inlineArea

        return HomelandOrnamentRecord(
            flags: flags,
            homeID: readUInt32(bytes, 2),
            rawPosition: HomelandVector3(
                x: Int(readInt16(bytes, 6)),
                y: Int(readInt16(bytes, 8)),
                z: Int(readInt16(bytes, 10))
            ),
            rawRotation: rotation,
            rawScale: scale,
            trashID: trashID,
            areaID: areaID,
            electricMode: flags & electric != 0
        )
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readInt16(_ bytes: [UInt8], _ offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(bytes, offset))
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
