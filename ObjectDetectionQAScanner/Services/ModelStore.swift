import Foundation
import Combine
import CoreML

// モデルの永続化レイヤ。
// 将来クラウド同期やSQLite化する場合も、ここを差し替えることでUI層への影響を最小化できる。
final class ModelStore: ObservableObject {
    @Published private(set) var models: [StoredModel] = []
    @Published var activeModelID: String?

    let settingsURL: URL
    private let registryURL: URL
    private let rootDir: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDir = support.appendingPathComponent("ModelRegistry", isDirectory: true)
        registryURL = rootDir.appendingPathComponent("registry.json")
        settingsURL = rootDir.appendingPathComponent("stability_settings.json")
        try? FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        loadRegistry()
    }

    func compiledURL(for model: StoredModel) -> URL {
        rootDir.appendingPathComponent(model.compiledModelPath)
    }

    func importModelZip(from zipURL: URL) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("model-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // iOS 16+ supports ZIP extraction through FileManager APIs.
        try FileManager.default.unzipItem(at: zipURL, to: tempDir)

        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        let metadataData = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(ModelMetadata.self, from: metadataData)

        let mlmodel = tempDir.appendingPathComponent("model.mlmodel")
        let mlpackage = tempDir.appendingPathComponent("model.mlpackage")
        let sourceModelURL: URL
        if FileManager.default.fileExists(atPath: mlmodel.path) {
            sourceModelURL = mlmodel
        } else {
            sourceModelURL = mlpackage
        }

        let compiledTemp = try MLModel.compileModel(at: sourceModelURL)
        let targetDir = rootDir.appendingPathComponent(metadata.modelID, isDirectory: true)
        try? FileManager.default.removeItem(at: targetDir)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let compiledTarget = targetDir.appendingPathComponent("model.mlmodelc", isDirectory: true)
        try FileManager.default.copyItem(at: compiledTemp, to: compiledTarget)

        let stored = StoredModel(
            id: metadata.modelID,
            metadata: metadata,
            importedAt: Date(),
            compiledModelPath: "\(metadata.modelID)/model.mlmodelc"
        )

        models.removeAll { $0.id == stored.id }
        models.append(stored)
        models.sort { $0.importedAt > $1.importedAt }
        if activeModelID == nil {
            activeModelID = stored.id
        }
        try persistRegistry()
    }

    func setActive(modelID: String) {
        activeModelID = modelID
    }

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([StoredModel].self, from: data) {
            models = decoded
            activeModelID = decoded.first?.id
        }
    }

    private func persistRegistry() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(models)
        try data.write(to: registryURL, options: .atomic)
    }
}
