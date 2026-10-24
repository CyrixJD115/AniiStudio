import Foundation

indirect enum PMDataValue: Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case table([String: PMDataValue])

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
    var table: [String: PMDataValue]? {
        if case .table(let value) = self { return value }
        return nil
    }
    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }
}

enum PMDataDecoderError: LocalizedError {
    case malformed(String)
    case missingTable(String)

    var errorDescription: String? {
        switch self {
        case .malformed(let detail): return "The installed Aniimo static database is malformed: \(detail)"
        case .missingTable(let name): return "The installed Aniimo static database does not contain \(name)."
        }
    }
}

/// Bounded decoder for Aniimo's pmdata BDD table container. All offsets are
/// validated against the current file and recursion/table sizes are capped.
struct PMDataDecoder {
    private struct Layout {
        let handle: Int
        let keys: Int
        let valueTypes: Int
        let values: Int
        let keyType: Int
        let count: Int
        let numericKeyCount: Int
        let offsetType: Int
    }

    private let data: Data
    private let widths = [8, 1, 1, 2, 2, 4, 4, 4, 4, 1]
    private let maximumTableCount = 50_000
    private let maximumDepth = 16

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 4 else { throw PMDataDecoderError.malformed("file is too small") }
    }

    func decodeTable(named name: String) throws -> [String: PMDataValue] {
        let handle = try tableHandle(named: name)
        var activeHandles = Set<Int>()
        return try decodeTable(handle: handle, depth: 0, activeHandles: &activeHandles)
    }

    func tableHandle(named name: String) throws -> Int {
        let root = Int(try uint32(at: data.count - 4))
        let layout = try tableLayout(handle: root)
        for index in 0..<layout.count where try key(at: index, layout: layout) == name {
            let (type, address) = try valueLocation(at: index, layout: layout)
            guard type == 8 else { throw PMDataDecoderError.malformed("root value for \(name) is not a table") }
            return Int(try uint32(at: address))
        }
        throw PMDataDecoderError.missingTable(name)
    }

    private func decodeTable(handle: Int, depth: Int, activeHandles: inout Set<Int>) throws -> [String: PMDataValue] {
        guard depth <= maximumDepth else { throw PMDataDecoderError.malformed("table nesting exceeds \(maximumDepth)") }
        guard activeHandles.insert(handle).inserted else {
            throw PMDataDecoderError.malformed("cyclic table reference at 0x\(String(handle, radix: 16))")
        }
        defer { activeHandles.remove(handle) }
        let layout = try tableLayout(handle: handle)
        var result: [String: PMDataValue] = [:]
        result.reserveCapacity(layout.count)
        for index in 0..<layout.count {
            let key = try key(at: index, layout: layout)
            let (type, address) = try valueLocation(at: index, layout: layout)
            let value: PMDataValue
            switch type {
            case 0...6:
                value = .number(try numericDouble(at: address, type: type))
            case 7:
                value = .string(try string(at: Int(try uint32(at: address))))
            case 8:
                value = .table(try decodeTable(
                    handle: Int(try uint32(at: address)),
                    depth: depth + 1,
                    activeHandles: &activeHandles
                ))
            case 9:
                value = .bool(try byte(at: address) == 1)
            default:
                throw PMDataDecoderError.malformed("unsupported value type \(type)")
            }
            result[key] = value
        }
        return result
    }

    private func tableLayout(handle: Int) throws -> Layout {
        let descriptor = Int(try uint32(at: handle))
        let keys = Int(try uint32(at: descriptor))
        let valueTypes = Int(try uint32(at: descriptor + 4))
        let values = Int(try uint32(at: descriptor + 8))
        let keyType = Int(try byte(at: keys + 4))
        let count = Int(try uint32(at: keys + 5))
        let numericKeyCount = Int(try uint32(at: keys + 9))
        let offsetType = Int(try byte(at: values))
        guard widths.indices.contains(keyType), widths.indices.contains(offsetType),
              count >= 0, count <= maximumTableCount,
              numericKeyCount >= 0, numericKeyCount <= count else {
            throw PMDataDecoderError.malformed("invalid table layout at 0x\(String(handle, radix: 16))")
        }
        try require(valueTypes, count)
        try require(keys + 13, numericKeyCount * widths[keyType] + (count - numericKeyCount) * 4)
        try require(values + 1, count * widths[offsetType])
        return Layout(
            handle: handle, keys: keys, valueTypes: valueTypes, values: values,
            keyType: keyType, count: count, numericKeyCount: numericKeyCount, offsetType: offsetType
        )
    }

    private func key(at index: Int, layout: Layout) throws -> String {
        if index < layout.numericKeyCount {
            let address = layout.keys + 13 + index * widths[layout.keyType]
            let value = try numericDouble(at: address, type: layout.keyType)
            return value.rounded() == value ? String(Int64(value)) : String(value)
        }
        let strings = layout.keys + 13 + layout.numericKeyCount * widths[layout.keyType]
        let pointer = Int(try uint32(at: strings + (index - layout.numericKeyCount) * 4))
        return try string(at: pointer)
    }

    private func valueLocation(at index: Int, layout: Layout) throws -> (type: Int, address: Int) {
        var type = Int(try byte(at: layout.valueTypes + index))
        let slot = layout.values + 1 + index * widths[layout.offsetType]
        let offset = try numericInteger(at: slot, type: layout.offsetType)
        let address64 = type >= 100 ? Int64(slot) - offset : Int64(layout.handle) + offset
        if type >= 100 { type -= 100 }
        guard address64 >= 0, address64 < Int64(data.count) else {
            throw PMDataDecoderError.malformed("value offset is outside the file")
        }
        return (type, Int(address64))
    }

    private func numericDouble(at offset: Int, type: Int) throws -> Double {
        switch type {
        case 0: return Double(bitPattern: try uint64(at: offset))
        case 1: return Double(try byte(at: offset))
        case 2: return Double(Int8(bitPattern: try byte(at: offset)))
        case 3: return Double(try uint16(at: offset))
        case 4: return Double(Int16(bitPattern: try uint16(at: offset)))
        case 5: return Double(try uint32(at: offset))
        case 6: return Double(Int32(bitPattern: try uint32(at: offset)))
        default: throw PMDataDecoderError.malformed("unsupported numeric type \(type)")
        }
    }

    private func numericInteger(at offset: Int, type: Int) throws -> Int64 {
        switch type {
        case 0: return Int64(try numericDouble(at: offset, type: type))
        case 1: return Int64(try byte(at: offset))
        case 2: return Int64(Int8(bitPattern: try byte(at: offset)))
        case 3: return Int64(try uint16(at: offset))
        case 4: return Int64(Int16(bitPattern: try uint16(at: offset)))
        case 5: return Int64(try uint32(at: offset))
        case 6: return Int64(Int32(bitPattern: try uint32(at: offset)))
        default: throw PMDataDecoderError.malformed("unsupported offset type \(type)")
        }
    }

    private func string(at offset: Int) throws -> String {
        guard offset >= 0, offset < data.count else { throw PMDataDecoderError.malformed("string offset outside file") }
        let limit = min(data.count, offset + 1_048_576)
        guard let terminator = data[offset..<limit].firstIndex(of: 0),
              let value = String(data: data[offset..<terminator], encoding: .utf8) else {
            throw PMDataDecoderError.malformed("invalid UTF-8 string")
        }
        return value
    }

    private func byte(at offset: Int) throws -> UInt8 {
        try require(offset, 1)
        return data[offset]
    }

    private func uint16(at offset: Int) throws -> UInt16 {
        try require(offset, 2)
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func uint32(at offset: Int) throws -> UInt32 {
        try require(offset, 4)
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private func uint64(at offset: Int) throws -> UInt64 {
        try require(offset, 8)
        var value: UInt64 = 0
        for index in 0..<8 { value |= UInt64(data[offset + index]) << UInt64(index * 8) }
        return value
    }

    private func require(_ offset: Int, _ count: Int) throws {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else {
            throw PMDataDecoderError.malformed("read outside file bounds")
        }
    }
}
