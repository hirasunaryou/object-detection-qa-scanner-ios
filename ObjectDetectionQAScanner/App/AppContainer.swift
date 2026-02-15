import Foundation
import Combine

@MainActor
final class AppContainer: ObservableObject {
    let debugLogStore = DebugLogStore.shared
    let modelStore: ModelStore
    let cameraManager = CameraManager()
    let inferenceEngine: InferenceEngine
    let logStore: LogStore
    let exporter: Exporter


    init() {
        self.modelStore = ModelStore(debugLogStore: debugLogStore)
        self.inferenceEngine = InferenceEngine(debugLogStore: debugLogStore)
        self.logStore = LogStore(debugLogStore: debugLogStore)
        self.exporter = Exporter(debugLogStore: debugLogStore)
    }

    lazy var settingsStore = SettingsStore(url: modelStore.settingsURL)
    lazy var liveViewModel = LiveViewModel(
        cameraManager: cameraManager,
        inferenceEngine: inferenceEngine,
        logStore: logStore,
        settingsStore: settingsStore,
        activeModelProvider: { [weak self] in
            guard let self, let id = self.modelStore.activeModelID else { return nil }
            return self.modelStore.models.first(where: { $0.id == id })
        }
    )

    lazy var modelsViewModel = ModelsViewModel(modelStore: modelStore, settingsStore: settingsStore)
    lazy var reportsViewModel = ReportsViewModel(logStore: logStore)

    func activateCurrentModelIfPossible() {
        guard
            let activeID = modelStore.activeModelID,
            let model = modelStore.models.first(where: { $0.id == activeID })
        else { return }
        try? liveViewModel.applyModel(model, from: modelStore)
    }
}
