import Foundation
import Combine
import CoreML
import ZipFoundation

// モデルの永続化レイヤ。
// 将来クラウド同期やSQLite化する場合も、ここを差し替えることでUI層への影響を最小化できる。
final class ModelStore: ObservableObject {
    @Published private(set) var models: [StoredModel] = []
    @Published var activeModelID: String?

    let settingsURL: URL
    private let registryURL: URL
    private let activeModelIDURL: URL
    private let rootDir: URL

    private enum ModelStoreError: LocalizedError {
        case zipOpenFailed
        case missingMetadata
        case missingModelAsset
        case invalidZipEntryPath(String)

        var errorDescription: String? {
            switch self {
            case .zipOpenFailed:
                return "ZIPファイルを開けませんでした。"
            case .missingMetadata:
                return "metadata.json がZIP内に見つかりません。"
            case .missingModelAsset:
                return "model.mlpackage または model.mlmodel がZIP内に見つかりません。"
            case .invalidZipEntryPath(let path):
                return "不正なZIPエントリパスです: \(path)"
            }
        }
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDir = support.appendingPathComponent("ModelRegistry", isDirectory: true)
        registryURL = rootDir.appendingPathComponent("registry.json")
        settingsURL = rootDir.appendingPathComponent("stability_settings.json")
        activeModelIDURL = rootDir.appendingPathComponent("active_model_id.txt")
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        loadRegistry()
    }

    func compiledURL(for model: StoredModel) -> URL {
        rootDir.appendingPathComponent(model.compiledModelPath)
    }

    func importModelZip(from zipURL: URL) throws {
        let fileManager = FileManager.default
        let tempExtractDir = fileManager.temporaryDirectory
            .appendingPathComponent("ModelImport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempExtractDir) }

        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw ModelStoreError.zipOpenFailed
        }

        // ZIP Slip対策として、展開前にエントリパスを検証する。
        for entry in archive {
            let entryPath = NSString(string: entry.path).standardizingPath
            if entryPath.hasPrefix("../") || entryPath == ".." {
                throw ModelStoreError.invalidZipEntryPath(entry.path)
            }
            let destinationURL = tempExtractDir.appendingPathComponent(entryPath)
            let destinationDir = destinationURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: destinationURL)
        }

        guard let metadataURL = findFirstNamed("metadata.json", in: tempExtractDir) else {
            throw ModelStoreError.missingMetadata
        }
        let metadata = try decodeMetadata(at: metadataURL)

        guard let modelSourceURL = findModelSource(in: tempExtractDir) else {
            throw ModelStoreError.missingModelAsset
        }

        let compiledURL = try MLModel.compileModel(at: modelSourceURL)
        let modelFolder = rootDir.appendingPathComponent(metadata.modelID, isDirectory: true)
        let persistedCompiledURL = modelFolder.appendingPathComponent("model.mlmodelc", isDirectory: true)

        try fileManager.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: persistedCompiledURL.path) {
            try fileManager.removeItem(at: persistedCompiledURL)
        }
        try fileManager.copyItem(at: compiledURL, to: persistedCompiledURL)

        let stored = StoredModel(
            id: metadata.modelID,
            metadata: metadata,
            importedAt: Date(),
            compiledModelPath: "\(metadata.modelID)/model.mlmodelc"
        )

        if let existingIndex = models.firstIndex(where: { $0.id == stored.id }) {
            models[existingIndex] = stored
        } else {
            models.append(stored)
        }

        models.sort { $0.importedAt > $1.importedAt }
        setActive(modelID: stored.id)
        try persistRegistry()
    }

    func setActive(modelID: String) {
        activeModelID = modelID
        try? modelID.write(to: activeModelIDURL, atomically: true, encoding: .utf8)
    }

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([StoredModel].self, from: data) {
            models = decoded
            if let activeID = try? String(contentsOf: activeModelIDURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               decoded.contains(where: { $0.id == activeID }) {
                activeModelID = activeID
            } else {
                activeModelID = decoded.first?.id
            }
        }
    }

    private func persistRegistry() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(models)
        try data.write(to: registryURL, options: .atomic)
    }

    private func decodeMetadata(at url: URL) throws -> ModelMetadata {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ModelMetadata.self, from: data)
    }

    private func findFirstNamed(_ filename: String, in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == filename {
                return fileURL
            }
        }
        return nil
    }

    private func findModelSource(in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent == "model.mlpackage" || fileURL.lastPathComponent == "model.mlmodel" {
                return fileURL
            }
        }
        return nil
    }
}
