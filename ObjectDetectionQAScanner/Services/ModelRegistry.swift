import CoreML
import Foundation

/// 端末内モデルの取り込み/永続化/アクティブ管理を担当。
final class ModelRegistry: ObservableObject {
    @Published private(set) var installedModels: [InstalledModel] = []
    @Published var activeModelID: String?
    @Published var settings: ScanSettings = .default

    private let fm = FileManager.default

    private var rootDirectory: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("models", isDirectory: true)
    }

    private var registryURL: URL { rootDirectory.appendingPathComponent("registry.json") }

    init() {
        try? fm.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        loadRegistry()
    }

    var activeModel: InstalledModel? {
        installedModels.first(where: { $0.id == activeModelID })
    }

    /// ZIPを展開し metadata 読み込み -> CoreML compile -> registry保存まで実施。
    func importModelZip(from zipURL: URL) throws {
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try ZipArchiveHelper.unzip(source: zipURL, destination: tempDir)

        let metadataURL = tempDir.appendingPathComponent("metadata.json")
        let metadataData = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(ModelManifest.self, from: metadataData)

        let mlmodelURL = ["model.mlmodel", "model.mlpackage"]
            .map { tempDir.appendingPathComponent($0) }
            .first(where: { fm.fileExists(atPath: $0.path) })

        guard let modelURL = mlmodelURL else {
            throw NSError(domain: "model", code: 1, userInfo: [NSLocalizedDescriptionKey: "model.mlmodel or model.mlpackage is required"])
        }

        let compiledURL = try MLModel.compileModel(at: modelURL)
        let modelDir = rootDirectory.appendingPathComponent(manifest.modelID, isDirectory: true)
        try? fm.removeItem(at: modelDir)
        try fm.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let compiledDest = modelDir.appendingPathComponent("model.mlmodelc")
        try fm.copyItem(at: compiledURL, to: compiledDest)

        let metadataDest = modelDir.appendingPathComponent("metadata.json")
        try fm.copyItem(at: metadataURL, to: metadataDest)

        let installed = InstalledModel(id: manifest.modelID,
                                       manifest: manifest,
                                       compiledModelPath: compiledDest.path,
                                       importedAt: Date())
        installedModels.removeAll { $0.id == installed.id }
        installedModels.append(installed)
        if activeModelID == nil { activeModelID = installed.id }
        saveRegistry()
    }

    private func saveRegistry() {
        let payload = RegistryPayload(models: installedModels, activeModelID: activeModelID, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: registryURL)
    }

    func persistSettings() { saveRegistry() }

    func setActiveModel(id: String) {
        activeModelID = id
        saveRegistry()
    }

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(RegistryPayload.self, from: data) else { return }
        installedModels = payload.models
        activeModelID = payload.activeModelID
        settings = payload.settings
    }

    private struct RegistryPayload: Codable {
        let models: [InstalledModel]
        let activeModelID: String?
        let settings: ScanSettings
    }
}
