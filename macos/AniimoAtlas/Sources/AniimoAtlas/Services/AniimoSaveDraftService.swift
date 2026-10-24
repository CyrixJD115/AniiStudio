import CryptoKit
import Foundation
import libzstd

enum AniimoSavePathComponent: Hashable {
    case key(String)
    case index(Int)

    var display: String {
        switch self {
        case .key(let key): return key
        case .index(let index): return "[\(index)]"
        }
    }
}

struct AniimoSaveField: Identifiable {
    let path: [AniimoSavePathComponent]
    let kind: String
    let isEditable: Bool
    let originalValue: String
    var value: String

    var id: String { path.map(\.display).joined(separator: ".") }
    var isChanged: Bool { value != originalValue }
}

struct AniimoSaveDraftManifest: Codable {
    let sourceFilename: String
    let sourceSHA256: String
    let sourceBytes: Int
    let decodedBytes: Int
    let createdAt: Date
    var exportedAt: Date?
    var appliedAt: Date?
    var editedFieldCount: Int
}

struct AniimoSaveDraft {
    let directory: URL
    let document: AniimoClientCacheDocument
    let manifest: AniimoSaveDraftManifest
    var fields: [AniimoSaveField]
}

enum AniimoSaveDraftError: LocalizedError {
    case invalidValue(path: String, expected: String)
    case pathNotFound(String)
    case compressionFailed(String)
    case verificationFailed
    case sourceChanged
    case gameRunning
    case noExport

    var errorDescription: String? {
        switch self {
        case .invalidValue(let path, let expected): return "\(path) needs a valid \(expected) value."
        case .pathNotFound(let path): return "The field \(path) no longer exists in this document."
        case .compressionFailed(let message): return "Zstandard compression failed: \(message)"
        case .verificationFailed: return "The rebuilt draft could not be decoded and verified."
        case .sourceChanged: return "The GameHub source changed after this draft was opened. Scan again and create a fresh draft."
        case .gameRunning: return "Aniimo.exe is running. Exit the game cleanly before applying a local cache draft."
        case .noExport: return "Export and verify the current draft before applying it."
        }
    }
}

struct AniimoSaveDraftService {
    private let decoder = AniimoClientCacheDecoder()
    private let encoder = AniimoMessagePackEncoder()
    private let requireGameClosed: Bool

    init(requireGameClosed: Bool = true) {
        self.requireGameClosed = requireGameClosed
    }

    func create(from sourceURL: URL) throws -> AniimoSaveDraft {
        let document = try decoder.decode(sourceURL)
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/SaveDrafts", isDirectory: true)
        let identifier = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8)
        let directory = root.appendingPathComponent(String(identifier), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try document.compressedData.write(to: directory.appendingPathComponent("original-client-info.zst"), options: [.atomic])
        try document.decodedData.write(to: directory.appendingPathComponent("original-client-info.msgpack"), options: [.atomic])

        let manifest = AniimoSaveDraftManifest(
            sourceFilename: sourceURL.lastPathComponent,
            sourceSHA256: SHA256.hash(data: document.compressedData).map { String(format: "%02x", $0) }.joined(),
            sourceBytes: document.compressedData.count,
            decodedBytes: document.decodedData.count,
            createdAt: Date(),
            exportedAt: nil,
            appliedAt: nil,
            editedFieldCount: 0
        )
        try writeManifest(manifest, to: directory)
        return AniimoSaveDraft(directory: directory, document: document, manifest: manifest, fields: flatten(document.root))
    }

    func export(_ draft: AniimoSaveDraft) throws -> URL {
        var root = draft.document.root
        let changed = draft.fields.filter(\.isChanged)
        for field in changed {
            try replace(path: field.path, value: field.value, kind: field.kind, in: &root)
        }
        let decoded = encoder.encode(root)
        let compressed = try compress(decoded)
        let output = draft.directory.appendingPathComponent("edited-client-info.zst")
        let decodedOutput = draft.directory.appendingPathComponent("edited-client-info.msgpack")
        try compressed.write(to: output, options: [.atomic])
        try decoded.write(to: decodedOutput, options: [.atomic])

        let verified = try decoder.decode(output)
        guard verified.decodedData == decoded else { throw AniimoSaveDraftError.verificationFailed }
        var manifest = draft.manifest
        manifest.exportedAt = Date()
        manifest.editedFieldCount = changed.count
        try writeManifest(manifest, to: draft.directory)
        return output
    }

    func apply(exportedURL: URL, to draft: AniimoSaveDraft) throws -> URL {
        guard FileManager.default.fileExists(atPath: exportedURL.path) else { throw AniimoSaveDraftError.noExport }
        guard !requireGameClosed || !isAniimoRunning() else { throw AniimoSaveDraftError.gameRunning }
        let sourceData = try Data(contentsOf: draft.document.sourceURL, options: .mappedIfSafe)
        let currentHash = SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
        guard currentHash == draft.manifest.sourceSHA256 else { throw AniimoSaveDraftError.sourceChanged }

        let exported = try decoder.decode(exportedURL)
        let backupURL = draft.directory.appendingPathComponent("pre-apply-backup.zst")
        try sourceData.write(to: backupURL, options: [.atomic])
        do {
            try exported.compressedData.write(to: draft.document.sourceURL, options: [.atomic])
            let applied = try decoder.decode(draft.document.sourceURL)
            guard applied.decodedData == exported.decodedData else { throw AniimoSaveDraftError.verificationFailed }
        } catch {
            try? sourceData.write(to: draft.document.sourceURL, options: [.atomic])
            throw error
        }

        var manifest = draft.manifest
        manifest.appliedAt = Date()
        manifest.editedFieldCount = draft.fields.filter(\.isChanged).count
        try writeManifest(manifest, to: draft.directory)
        return backupURL
    }

    func prettyText(for value: MessagePackValue) -> String {
        render(value, depth: 0)
    }

    private func flatten(_ value: MessagePackValue, path: [AniimoSavePathComponent] = []) -> [AniimoSaveField] {
        switch value {
        case .map(let values):
            return values.keys.sorted().flatMap { key in flatten(values[key]!, path: path + [.key(key)]) }
        case .array(let values):
            return values.enumerated().flatMap { index, value in flatten(value, path: path + [.index(index)]) }
        case .null, .binary:
            return []
        case .bool(let value):
            let text = value ? "true" : "false"
            return [field(path: path, kind: "boolean", value: text)]
        case .integer(let value):
            let text = String(value)
            return [field(path: path, kind: "integer", value: text)]
        case .unsigned(let value):
            let text = String(value)
            return [field(path: path, kind: "unsigned", value: text)]
        case .number(let value):
            let text = String(value)
            return [field(path: path, kind: "number", value: text)]
        case .string(let value):
            return [field(path: path, kind: "text", value: value)]
        }
    }

    private func field(path: [AniimoSavePathComponent], kind: String, value: String) -> AniimoSaveField {
        let protectedTerms = ["account", "auth", "credential", "platform", "server", "session", "ticket", "token", "uid", "user", "version"]
        let normalizedPath = path.map(\.display).joined(separator: ".").lowercased()
        let editable = !protectedTerms.contains(where: normalizedPath.contains)
        return AniimoSaveField(path: path, kind: kind, isEditable: editable, originalValue: value, value: value)
    }

    private func replace(path: [AniimoSavePathComponent], value: String, kind: String, in root: inout MessagePackValue) throws {
        guard let component = path.first else {
            switch kind {
            case "boolean":
                guard value == "true" || value == "false" else { throw AniimoSaveDraftError.invalidValue(path: "root", expected: kind) }
                root = .bool(value == "true")
            case "integer":
                guard let parsed = Int(value) else { throw AniimoSaveDraftError.invalidValue(path: "root", expected: kind) }
                root = .integer(parsed)
            case "unsigned":
                guard let parsed = UInt64(value) else { throw AniimoSaveDraftError.invalidValue(path: "root", expected: kind) }
                root = .unsigned(parsed)
            case "number":
                guard let parsed = Double(value), parsed.isFinite else { throw AniimoSaveDraftError.invalidValue(path: "root", expected: kind) }
                root = .number(parsed)
            case "text": root = .string(value)
            default: throw AniimoSaveDraftError.invalidValue(path: "root", expected: kind)
            }
            return
        }

        let remainder = Array(path.dropFirst())
        switch (component, root) {
        case (.key(let key), .map(var values)):
            guard var child = values[key] else { throw AniimoSaveDraftError.pathNotFound(key) }
            try replace(path: remainder, value: value, kind: kind, in: &child)
            values[key] = child
            root = .map(values)
        case (.index(let index), .array(var values)) where values.indices.contains(index):
            var child = values[index]
            try replace(path: remainder, value: value, kind: kind, in: &child)
            values[index] = child
            root = .array(values)
        default:
            throw AniimoSaveDraftError.pathNotFound(path.map(\.display).joined(separator: "."))
        }
    }

    func compress(_ data: Data) throws -> Data {
        var output = Data(count: ZSTD_compressBound(data.count))
        let result = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                ZSTD_compress(destination.baseAddress, destination.count, source.baseAddress, source.count, 6)
            }
        }
        guard ZSTD_isError(result) == 0 else {
            throw AniimoSaveDraftError.compressionFailed(String(cString: ZSTD_getErrorName(result)))
        }
        output.count = result
        return output
    }

    private func writeManifest(_ manifest: AniimoSaveDraftManifest, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: [.atomic])
    }

    private func isAniimoRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-if", "Aniimo\\.exe"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return true }
    }

    private func render(_ value: MessagePackValue, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let childIndent = String(repeating: "  ", count: depth + 1)
        switch value {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .unsigned(let value): return "\(value)u"
        case .number(let value): return String(value)
        case .string(let value):
            let data = try? JSONEncoder().encode(value)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(value)\""
        case .binary(let data): return "<binary \(data.count) bytes>"
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            return "[\n" + values.map { childIndent + render($0, depth: depth + 1) }.joined(separator: ",\n") + "\n\(indent)]"
        case .map(let values):
            guard !values.isEmpty else { return "{}" }
            return "{\n" + values.keys.sorted().map { key in
                let encodedKey = (try? JSONEncoder().encode(key)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(key)\""
                return childIndent + encodedKey + ": " + render(values[key]!, depth: depth + 1)
            }.joined(separator: ",\n") + "\n\(indent)}"
        }
    }
}
