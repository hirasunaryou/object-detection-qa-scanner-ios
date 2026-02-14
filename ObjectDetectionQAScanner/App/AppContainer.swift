import Foundation

final class AppContainer: ObservableObject {
    let modelRegistry: ModelRegistry
    let logStore: LogStore
    let stabilityEvaluator: StabilityEvaluator
    let inferenceEngine: InferenceEngine
    let cameraManager: CameraManager

    init() {
        self.modelRegistry = ModelRegistry()
        self.logStore = LogStore()
        self.stabilityEvaluator = StabilityEvaluator()
        self.inferenceEngine = InferenceEngine()
        self.cameraManager = CameraManager()
    }
}
