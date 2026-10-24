import Foundation
import libzstd

struct AniimoClientCacheRecord: Identifiable, Sendable {
    let name: String
    let kind: String
    let detail: String
    var id: String { name }
}

struct AniimoClientCacheSummary: Identifiable, Sendable {
    let url: URL
    let compressedBytes: Int
    let decodedBytes: Int
    let version: Int?
    let recordCount: Int
    let homelandRecordCount: Int
    let recordGroups: [String]
    let records: [AniimoClientCacheRecord]
    var id: String { url.path }
}

struct AniimoClientCacheDocument {
    let sourceURL: URL
    let compressedData: Data
    let decodedData: Data
    let root: MessagePackValue
}

enum AniimoClientCacheDecoderError: LocalizedError {
    case invalidZstandardFrame
    case unknownDecodedSize
    case decompressionFailed(String)
    case invalidMessagePack

    var errorDescription: String? {
        switch self {
        case .invalidZstandardFrame: return "The client cache is not a valid Zstandard frame."
        case .unknownDecodedSize: return "The client cache does not publish its decoded size."
        case .decompressionFailed(let message): return "Zstandard decoding failed: \(message)"
        case .invalidMessagePack: return "The decoded client cache is not recognized MessagePack data."
        }
    }
}

struct AniimoClientCacheDecoder {
    func inspect(_ url: URL) throws -> AniimoClientCacheSummary {
        let document = try decode(url)
        return try inspectDecoded(document.decodedData, source: url, compressedBytes: document.compressedData.count)
    }

    func decode(_ url: URL) throws -> AniimoClientCacheDocument {
        let compressed = try Data(contentsOf: url, options: .mappedIfSafe)
        let decoded = try decompress(compressed)
        var parser = MessagePackParser(data: decoded)
        let root = try parser.read()
        guard case .map = root else { throw AniimoClientCacheDecoderError.invalidMessagePack }
        return AniimoClientCacheDocument(sourceURL: url, compressedData: compressed, decodedData: decoded, root: root)
    }

    func inspectDecoded(_ decoded: Data, source: URL, compressedBytes: Int) throws -> AniimoClientCacheSummary {
        var parser = MessagePackParser(data: decoded)
        guard case .map(let root) = try parser.read(), case .map(let records)? = root["records"] else {
            throw AniimoClientCacheDecoderError.invalidMessagePack
        }
        let version = root["version"]?.integer
        let names = records.keys.sorted()
        let homelandNames = names.filter { name in
            let lowered = name.lowercased()
            return lowered.contains("home") || lowered.contains("camp") || lowered.contains("house") || lowered.contains("furniture")
        }
        let groups = Dictionary(grouping: names) { name -> String in
            let separators = CharacterSet(charactersIn: "._-0123456789")
            return name.components(separatedBy: separators).first(where: { !$0.isEmpty }) ?? "Other"
        }.map { "\($0.key) · \($0.value.count)" }.sorted()
        let recordRows = names.compactMap { name -> AniimoClientCacheRecord? in
            guard let value = records[name] else { return nil }
            return AniimoClientCacheRecord(name: name, kind: value.kind, detail: value.summary)
        }
        return AniimoClientCacheSummary(
            url: source,
            compressedBytes: compressedBytes,
            decodedBytes: decoded.count,
            version: version,
            recordCount: records.count,
            homelandRecordCount: homelandNames.count,
            recordGroups: groups,
            records: recordRows
        )
    }

    func decompress(_ data: Data) throws -> Data {
        let contentSize = data.withUnsafeBytes { bytes in
            ZSTD_getFrameContentSize(bytes.baseAddress, data.count)
        }
        guard contentSize != UInt64.max else { throw AniimoClientCacheDecoderError.invalidZstandardFrame }
        guard contentSize != UInt64.max - 1, contentSize <= 64 * 1024 * 1024 else { throw AniimoClientCacheDecoderError.unknownDecodedSize }
        var output = Data(count: Int(contentSize))
        let result = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                ZSTD_decompress(destination.baseAddress, destination.count, source.baseAddress, source.count)
            }
        }
        guard ZSTD_isError(result) == 0 else {
            let message = String(cString: ZSTD_getErrorName(result))
            throw AniimoClientCacheDecoderError.decompressionFailed(message)
        }
        output.count = result
        return output
    }
}

indirect enum MessagePackValue {
    case null, bool(Bool), integer(Int), unsigned(UInt64), number(Double), string(String), binary(Data), array([MessagePackValue]), map([String: MessagePackValue])
    var integer: Int? {
        switch self { case .integer(let value): return value; case .unsigned(let value): return Int(exactly: value); default: return nil }
    }
    var key: String? {
        switch self { case .string(let value): return value; case .integer(let value): return String(value); case .unsigned(let value): return String(value); default: return nil }
    }
    var kind: String {
        switch self {
        case .null: return "null"
        case .bool: return "boolean"
        case .integer, .unsigned: return "integer"
        case .number: return "number"
        case .string: return "text"
        case .binary: return "binary"
        case .array: return "array"
        case .map: return "map"
        }
    }
    var summary: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .unsigned(let value): return String(value)
        case .number(let value): return String(value)
        case .string(let value):
            let flattened = value.replacingOccurrences(of: "\n", with: " ")
            return flattened.count > 120 ? String(flattened.prefix(120)) + "…" : flattened
        case .binary(let value): return "\(value.count) bytes"
        case .array(let value): return "\(value.count) values"
        case .map(let value): return "\(value.count) fields"
        }
    }
}

struct AniimoMessagePackEncoder {
    func encode(_ value: MessagePackValue) -> Data {
        var output = Data()
        append(value, to: &output)
        return output
    }

    private func append(_ value: MessagePackValue, to output: inout Data) {
        switch value {
        case .null:
            output.append(0xc0)
        case .bool(let value):
            output.append(value ? 0xc3 : 0xc2)
        case .integer(let value):
            appendSigned(Int64(value), to: &output)
        case .unsigned(let value):
            appendUnsigned(value, to: &output)
        case .number(let value):
            output.append(0xcb)
            appendInteger(value.bitPattern, byteCount: 8, to: &output)
        case .string(let value):
            let data = Data(value.utf8)
            appendStringHeader(data.count, to: &output)
            output.append(data)
        case .binary(let data):
            appendBinaryHeader(data.count, to: &output)
            output.append(data)
        case .array(let values):
            appendArrayHeader(values.count, to: &output)
            values.forEach { append($0, to: &output) }
        case .map(let values):
            appendMapHeader(values.count, to: &output)
            for key in values.keys.sorted() {
                append(.string(key), to: &output)
                append(values[key]!, to: &output)
            }
        }
    }

    private func appendSigned(_ value: Int64, to output: inout Data) {
        if value >= 0 { appendUnsigned(UInt64(value), to: &output) }
        else if value >= -32 { output.append(UInt8(bitPattern: Int8(value))) }
        else if value >= Int64(Int8.min) { output.append(0xd0); output.append(UInt8(bitPattern: Int8(value))) }
        else if value >= Int64(Int16.min) { output.append(0xd1); appendInteger(UInt64(UInt16(bitPattern: Int16(value))), byteCount: 2, to: &output) }
        else if value >= Int64(Int32.min) { output.append(0xd2); appendInteger(UInt64(UInt32(bitPattern: Int32(value))), byteCount: 4, to: &output) }
        else { output.append(0xd3); appendInteger(UInt64(bitPattern: value), byteCount: 8, to: &output) }
    }

    private func appendUnsigned(_ value: UInt64, to output: inout Data) {
        if value <= 0x7f { output.append(UInt8(value)) }
        else if value <= UInt64(UInt8.max) { output.append(0xcc); output.append(UInt8(value)) }
        else if value <= UInt64(UInt16.max) { output.append(0xcd); appendInteger(value, byteCount: 2, to: &output) }
        else if value <= UInt64(UInt32.max) { output.append(0xce); appendInteger(value, byteCount: 4, to: &output) }
        else { output.append(0xcf); appendInteger(value, byteCount: 8, to: &output) }
    }

    private func appendStringHeader(_ count: Int, to output: inout Data) {
        if count <= 31 { output.append(0xa0 | UInt8(count)) }
        else if count <= 255 { output.append(0xd9); output.append(UInt8(count)) }
        else if count <= 65_535 { output.append(0xda); appendInteger(UInt64(count), byteCount: 2, to: &output) }
        else { output.append(0xdb); appendInteger(UInt64(count), byteCount: 4, to: &output) }
    }

    private func appendBinaryHeader(_ count: Int, to output: inout Data) {
        if count <= 255 { output.append(0xc4); output.append(UInt8(count)) }
        else if count <= 65_535 { output.append(0xc5); appendInteger(UInt64(count), byteCount: 2, to: &output) }
        else { output.append(0xc6); appendInteger(UInt64(count), byteCount: 4, to: &output) }
    }

    private func appendArrayHeader(_ count: Int, to output: inout Data) {
        if count <= 15 { output.append(0x90 | UInt8(count)) }
        else if count <= 65_535 { output.append(0xdc); appendInteger(UInt64(count), byteCount: 2, to: &output) }
        else { output.append(0xdd); appendInteger(UInt64(count), byteCount: 4, to: &output) }
    }

    private func appendMapHeader(_ count: Int, to output: inout Data) {
        if count <= 15 { output.append(0x80 | UInt8(count)) }
        else if count <= 65_535 { output.append(0xde); appendInteger(UInt64(count), byteCount: 2, to: &output) }
        else { output.append(0xdf); appendInteger(UInt64(count), byteCount: 4, to: &output) }
    }

    private func appendInteger(_ value: UInt64, byteCount: Int, to output: inout Data) {
        for shift in stride(from: (byteCount - 1) * 8, through: 0, by: -8) {
            output.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }
}

private struct MessagePackParser {
    let data: Data
    var offset = 0

    mutating func read() throws -> MessagePackValue {
        let byte = try readByte()
        if byte <= 0x7f { return .unsigned(UInt64(byte)) }
        if byte >= 0xe0 { return .integer(Int(Int8(bitPattern: byte))) }
        if byte & 0xe0 == 0xa0 { return .string(try readString(Int(byte & 0x1f))) }
        if byte & 0xf0 == 0x90 { return .array(try readArray(Int(byte & 0x0f))) }
        if byte & 0xf0 == 0x80 { return .map(try readMap(Int(byte & 0x0f))) }
        switch byte {
        case 0xc0: return .null
        case 0xc2: return .bool(false)
        case 0xc3: return .bool(true)
        case 0xc4: return .binary(try readData(Int(try readUInt(1))))
        case 0xc5: return .binary(try readData(Int(try readUInt(2))))
        case 0xc6: return .binary(try readData(Int(try readUInt(4))))
        case 0xca: return .number(Double(Float(bitPattern: UInt32(try readUInt(4)))))
        case 0xcb: return .number(Double(bitPattern: try readUInt(8)))
        case 0xcc: return .unsigned(try readUInt(1))
        case 0xcd: return .unsigned(try readUInt(2))
        case 0xce: return .unsigned(try readUInt(4))
        case 0xcf: return .unsigned(try readUInt(8))
        case 0xd0: return .integer(Int(Int8(bitPattern: UInt8(try readUInt(1)))))
        case 0xd1: return .integer(Int(Int16(bitPattern: UInt16(try readUInt(2)))))
        case 0xd2: return .integer(Int(Int32(bitPattern: UInt32(try readUInt(4)))))
        case 0xd3: return .integer(Int(bitPattern: UInt(try readUInt(8))))
        case 0xd9: return .string(try readString(Int(try readUInt(1))))
        case 0xda: return .string(try readString(Int(try readUInt(2))))
        case 0xdb: return .string(try readString(Int(try readUInt(4))))
        case 0xdc: return .array(try readArray(Int(try readUInt(2))))
        case 0xdd: return .array(try readArray(Int(try readUInt(4))))
        case 0xde: return .map(try readMap(Int(try readUInt(2))))
        case 0xdf: return .map(try readMap(Int(try readUInt(4))))
        default: throw AniimoClientCacheDecoderError.invalidMessagePack
        }
    }

    private mutating func readMap(_ count: Int) throws -> [String: MessagePackValue] {
        var result: [String: MessagePackValue] = [:]
        for _ in 0..<count {
            let keyValue = try read()
            let value = try read()
            if let key = keyValue.key { result[key] = value }
        }
        return result
    }

    private mutating func readArray(_ count: Int) throws -> [MessagePackValue] {
        var result: [MessagePackValue] = []
        result.reserveCapacity(count)
        for _ in 0..<count { result.append(try read()) }
        return result
    }

    private mutating func readString(_ count: Int) throws -> String {
        guard let value = String(data: try readData(count), encoding: .utf8) else { throw AniimoClientCacheDecoderError.invalidMessagePack }
        return value
    }

    private mutating func readData(_ count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else { throw AniimoClientCacheDecoderError.invalidMessagePack }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    private mutating func readByte() throws -> UInt8 {
        guard offset < data.count else { throw AniimoClientCacheDecoderError.invalidMessagePack }
        defer { offset += 1 }
        return data[offset]
    }

    private mutating func readUInt(_ byteCount: Int) throws -> UInt64 {
        let bytes = try readData(byteCount)
        return bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}
