import Foundation

@MainActor
final class ModelsViewModel: ObservableObject {
    @Published var importError: String?

    let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    var models: [InstalledModel] { container.modelRegistry.installedModels.sorted(by: { $0.importedAt > $1.importedAt }) }
    var activeModelID: String? { container.modelRegistry.activeModelID }

    func importZip(url: URL) {
        do {
            try container.modelRegistry.importModelZip(from: url)
            if let active = container.modelRegistry.activeModel {
                try container.inferenceEngine.load(compiledModelURL: URL(fileURLWithPath: active.compiledModelPath))
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    func setActive(modelID: String) {
        container.modelRegistry.setActiveModel(id: modelID)
    }

    func saveSettings() {
        container.modelRegistry.persistSettings()
    }
}
