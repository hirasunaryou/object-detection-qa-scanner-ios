import Foundation
import Combine
import CoreML
import ZIPFoundation

// モデルの永続化レイヤ。
// 将来クラウド同期やSQLite化する場合も、ここを差し替えることでUI層への影響を最小化できる。
final class ModelStore: ObservableObject {
    enum ModelStoreError: LocalizedError {
        case failedToUnzip
        case missingMetadata
        case missingModelFile
        case invalidMetadata
        case invalidModelID

        var errorDescription: String? {
            switch self {
            case .failedToUnzip:
                return "ZIP の展開に失敗しました。"
            case .missingMetadata:
                return "metadata.json が ZIP 内に見つかりません。"
            case .missingModelFile:
                return "model.mlpackage または model.mlmodel が ZIP 内に見つかりません。"
            case .invalidMetadata:
                return "metadata.json の内容を読み取れませんでした（ISO8601形式の日付を確認してください）。"
            case .invalidModelID:
                return "metadata.model_id に使用できない文字が含まれています（英数字、._- のみ利用可）。"
            }
        }
    }

    @Published private(set) var models: [StoredModel] = []
    @Published var activeModelID: String?

    let settingsURL: URL
    private let registryURL: URL
    private let activeModelURL: URL
    private let rootDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDir = support.appendingPathComponent("ModelRegistry", isDirectory: true)
        registryURL = rootDir.appendingPathComponent("registry.json")
        activeModelURL = rootDir.appendingPathComponent("active_model_id.txt")
        settingsURL = rootDir.appendingPathComponent("stability_settings.json")
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        loadRegistry()
    }

    func compiledURL(for model: StoredModel) -> URL {
        rootDir.appendingPathComponent(model.compiledModelPath)
    }

    func importModelZip(from zipURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            // ZIPFoundation のAPIでZIPを安全に展開する（iOS 16対応）。
            try FileManager.default.unzipItem(at: zipURL, to: tempDir)
        } catch {
            throw ModelStoreError.failedToUnzip
        }

        guard let metadataURL = findFile(named: "metadata", withExtension: "json", under: tempDir) else {
            throw ModelStoreError.missingMetadata
        }

        let metadata = try decodeMetadata(from: metadataURL)
        try validateModelID(metadata.modelID)
        let sourceModelURL = try resolveSourceModelURL(under: tempDir)

        // compileModel(at:) は .mlmodel/.mlpackage の両方を受け取れるため、入力形式の違いを吸収できる。
        let compiledTempURL = try MLModel.compileModel(at: sourceModelURL)

        let modelDir = rootDir.appendingPathComponent(metadata.modelID, isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let targetCompiledURL = modelDir.appendingPathComponent("\(metadata.modelID).mlmodelc", isDirectory: true)
        if FileManager.default.fileExists(atPath: targetCompiledURL.path) {
            try FileManager.default.removeItem(at: targetCompiledURL)
        }
        try FileManager.default.copyItem(at: compiledTempURL, to: targetCompiledURL)

        let stored = StoredModel(
            id: metadata.modelID,
            metadata: metadata,
            importedAt: Date(),
            compiledModelPath: "\(metadata.modelID)/\(metadata.modelID).mlmodelc"
        )

        models.removeAll { $0.id == stored.id }
        models.append(stored)
        activeModelID = stored.id
        try persistRegistry()
        try persistActiveModelID()
    }

    func setActive(modelID: String) {
        activeModelID = modelID
        try? persistActiveModelID()
    }

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([StoredModel].self, from: data) {
            models = decoded
        }

        if
            let activeData = try? Data(contentsOf: activeModelURL),
            let activeID = String(data: activeData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !activeID.isEmpty,
            models.contains(where: { $0.id == activeID })
        {
            activeModelID = activeID
        } else {
            activeModelID = models.first?.id
        }
    }

    private func persistRegistry() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(models)
        try data.write(to: registryURL, options: .atomic)
    }

    private func persistActiveModelID() throws {
        guard let activeModelID, let data = activeModelID.data(using: .utf8) else { return }
        try data.write(to: activeModelURL, options: .atomic)
    }


    private func validateModelID(_ modelID: String) throws {
        // モデルIDはディレクトリ名/ファイル名にも使うため、安全な文字のみ許可する。
        // 許可: 英数字 + "." + "_" + "-"
        let pattern = "^[A-Za-z0-9._-]+$"
        let range = NSRange(location: 0, length: modelID.utf16.count)
        let regex = try NSRegularExpression(pattern: pattern)
        guard regex.firstMatch(in: modelID, options: [], range: range) != nil else {
            throw ModelStoreError.invalidModelID
        }
    }

    private func decodeMetadata(from metadataURL: URL) throws -> ModelMetadata {
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ModelMetadata.self, from: data)
        } catch {
            throw ModelStoreError.invalidMetadata
        }
    }

    private func resolveSourceModelURL(under root: URL) throws -> URL {
        if let packageURL = findItem(named: "model", withExtension: "mlpackage", under: root) {
            return packageURL
        }
        if let modelURL = findFile(named: "model", withExtension: "mlmodel", under: root) {
            return modelURL
        }
        throw ModelStoreError.missingModelFile
    }

    private func findFile(named name: String, withExtension fileExtension: String, under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "\(name).\(fileExtension)" {
                return fileURL
            }
        }
        return nil
    }

    private func findItem(named name: String, withExtension fileExtension: String, under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "\(name).\(fileExtension)" {
            return fileURL
        }
        return nil
    }
}
