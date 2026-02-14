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
        _ = zipURL
        // iOS 16 互換優先のため、ZIP import は一時的に無効化。
        // 将来は Compression / Archive 系API か独自展開ロジックで再実装予定。
        throw NSError(
            domain: "ModelStore",
            code: 2001,
            userInfo: [NSLocalizedDescriptionKey: "ZIP import is temporarily disabled on iOS 16 build."]
        )
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
