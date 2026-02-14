import Foundation
import Combine
import AVFoundation

@MainActor
// Live画面のオーケストレーター。
// カメラ -> 推論 -> 安定判定 -> UI更新/ログ保存 までを1つの責務として管理する。
final class LiveViewModel: ObservableObject {
    @Published var detections: [Detection] = []
    @Published var isStable = false
    @Published var stableReason = ""
    @Published var fps: Double = 0
    @Published var latencyMs: Double = 0
    @Published var flickerCount: Int = 0
    @Published var latestFrame: CMSampleBuffer?
    @Published var secondsToStable: Double?

    let cameraManager: CameraManager
    private let inferenceEngine: InferenceEngine
    private let stabilityEvaluator = StabilityEvaluator()
    private let logStore: LogStore
    private var settingsStore: SettingsStore
    private var activeModelProvider: () -> StoredModel?

    private var lastFrameTime = Date()

    init(
        cameraManager: CameraManager,
        inferenceEngine: InferenceEngine,
        logStore: LogStore,
        settingsStore: SettingsStore,
        activeModelProvider: @escaping () -> StoredModel?
    ) {
        self.cameraManager = cameraManager
        self.inferenceEngine = inferenceEngine
        self.logStore = logStore
        self.settingsStore = settingsStore
        self.activeModelProvider = activeModelProvider

        cameraManager.onFrame = { [weak self] sampleBuffer in
            Task { await self?.handleFrame(sampleBuffer) }
        }
    }

    func start() {
        cameraManager.requestPermissionAndConfigure()
        cameraManager.start()
        stabilityEvaluator.reset()
    }

    func stop() {
        cameraManager.stop()
    }

    func resetStabilityState() {
        stabilityEvaluator.reset()
    }

    func applyModel(_ model: StoredModel, from modelStore: ModelStore) throws {
        try inferenceEngine.loadModel(modelID: model.id, compiledModelURL: modelStore.compiledURL(for: model))
        resetStabilityState()
    }

    func saveConfirm() throws {
        try save(action: .confirm, reason: nil)
    }

    func saveNG(reason: NGReason) throws {
        try save(action: .ng, reason: reason)
    }

    private func save(action: ScanLogEntry.Action, reason: NGReason?) throws {
        guard let frame = latestFrame, let model = activeModelProvider() else { return }
        _ = try logStore.saveScan(
            modelID: model.id,
            action: action,
            ngReason: reason,
            isStable: isStable,
            latencyMs: latencyMs,
            fps: fps,
            detections: detections,
            flickerCount: flickerCount,
            secondsToStable: secondsToStable,
            sampleBuffer: frame
        )
        resetStabilityState()
    }

    private func handleFrame(_ sampleBuffer: CMSampleBuffer) async {
        latestFrame = sampleBuffer
        let now = Date()
        let delta = now.timeIntervalSince(lastFrameTime)
        lastFrameTime = now
        if delta > 0 {
            fps = 1.0 / delta
        }

        inferenceEngine.infer(sampleBuffer: sampleBuffer) { [weak self] detections, latency in
            Task { @MainActor in
                guard let self else { return }
                self.latencyMs = latency
                self.detections = detections

                let result = self.stabilityEvaluator.evaluate(detections: detections, settings: self.settingsStore.settings)
                self.isStable = result.isStable
                self.stableReason = result.reason
                self.flickerCount = result.flickerCount
                self.secondsToStable = result.secondsToStable
            }
        }
    }
}
