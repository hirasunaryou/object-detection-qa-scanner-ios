import Foundation
import Combine
import CoreML
import ZIPFoundation
import os

// モデルの永続化レイヤ。
// 将来クラウド同期やSQLite化する場合も、ここを差し替えることでUI層への影響を最小化できる。
final class ModelStore: ObservableObject {
    private static let logger = Logger(subsystem: "ObjectDetectionQAScanner", category: "ModelStore")

    enum SourceModelKind: String {
        case mlpackage
        case mlmodel
    }

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
                return "ZIP のルート直下に必要なファイルがありません。model.mlpackage/ または model.mlmodel に加えて metadata.json を配置してください。"
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
    private let debugLogStore: DebugLogStore

    init(debugLogStore: DebugLogStore = .shared) {
        self.debugLogStore = debugLogStore
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
        debugLogStore.info(
            tag: "ModelStore",
            message: "model_import_start",
            fields: ["zip_path": zipURL.path]
        )
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("model-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            // ZIPFoundation のAPIでZIPを安全に展開する（iOS 16対応）。
            try FileManager.default.unzipItem(at: zipURL, to: tempDir)
        } catch {
            debugLogStore.error(tag: "ModelStore", message: "model_import_unzip_failed", fields: ["zip_path": zipURL.path, "error": error.localizedDescription])
            throw ModelStoreError.failedToUnzip
        }

        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        guard isRegularFile(at: metadataURL) else {
            debugLogStore.warn(tag: "ModelStore", message: "model_import_validation_error", fields: ["reason": "missing_metadata", "zip_path": zipURL.path])
            throw ModelStoreError.missingMetadata
        }

        let metadata = try decodeMetadata(from: metadataURL)
        try validateModelID(metadata.modelID)
        let sourceModelURL: URL
        do {
            sourceModelURL = try resolveSourceModelURL(under: tempDir)
        } catch {
            debugLogStore.warn(tag: "ModelStore", message: "model_import_validation_error", fields: ["reason": "missing_model_file", "zip_path": zipURL.path])
            throw error
        }

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
        debugLogStore.info(
            tag: "ModelStore",
            message: "model_import_end",
            fields: [
                "model_id": metadata.modelID,
                "classes_count": metadata.classes.count,
                "compiled_path": targetCompiledURL.path
            ]
        )
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
            debugLogStore.warn(tag: "ModelStore", message: "model_import_validation_error", fields: ["reason": "invalid_model_id", "model_id": modelID])
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
            debugLogStore.warn(tag: "ModelStore", message: "model_import_validation_error", fields: ["reason": "invalid_metadata", "path": metadataURL.path])
            throw ModelStoreError.invalidMetadata
        }
    }

    static func resolveSourceModelKind(hasMLPackage: Bool, hasMLModel: Bool) throws -> SourceModelKind {
        if hasMLPackage {
            if hasMLModel {
                logger.info("Both model.mlpackage and model.mlmodel found in ZIP root. Selecting model.mlpackage.")
            } else {
                logger.info("Selected model.mlpackage from ZIP root.")
            }
            return .mlpackage
        }

        if hasMLModel {
            logger.info("Selected model.mlmodel from ZIP root.")
            return .mlmodel
        }

        throw ModelStoreError.missingModelFile
    }

    private func resolveSourceModelURL(under root: URL) throws -> URL {
        let modelPackageURL = root.appendingPathComponent("model.mlpackage", isDirectory: true)
        let modelFileURL = root.appendingPathComponent("model.mlmodel")

        let chosenKind = try Self.resolveSourceModelKind(
            hasMLPackage: isDirectory(at: modelPackageURL),
            hasMLModel: isRegularFile(at: modelFileURL)
        )

        switch chosenKind {
        case .mlpackage:
            return modelPackageURL
        case .mlmodel:
            return modelFileURL
        }
    }

    private func isRegularFile(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func isDirectory(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
