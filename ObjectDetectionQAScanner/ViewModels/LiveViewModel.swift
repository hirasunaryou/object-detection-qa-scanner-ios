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
    @Published var latestFrameDimensions: CGSize = .zero
    @Published var secondsToStable: Double?
    @Published var modelStatusText: String = "No model loaded"

    let cameraManager: CameraManager
    private let inferenceEngine: InferenceEngine
    private let stabilityEvaluator = StabilityEvaluator()
    private let logStore: LogStore
    private var settingsStore: SettingsStore
    private var activeModelProvider: () -> StoredModel?

    // 推論負荷を安定させるため、最大15fps相当で推論要求を間引きます。
    private let targetInferenceInterval: CFTimeInterval = 1.0 / 15.0
    private var isInferenceInFlight = false
    private var lastInferenceDispatchTime: CFAbsoluteTime = 0
    private var lastInferenceCompletionTime: CFAbsoluteTime = 0

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
        if inferenceEngine.activeModelID == nil {
            modelStatusText = "No model loaded"
        }
    }

    func stop() {
        cameraManager.stop()
    }

    func resetStabilityState() {
        stabilityEvaluator.reset()
    }

    func applyModel(_ model: StoredModel, from modelStore: ModelStore) throws {
        try inferenceEngine.loadModel(modelID: model.id, compiledModelURL: modelStore.compiledURL(for: model))
        modelStatusText = "Active model: \(model.metadata.displayName)"
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
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            latestFrameDimensions = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            )
        }

        if inferenceEngine.activeModelID == nil {
            detections = []
            isStable = false
            stableReason = "no_model"
            return
        }

        // 1) 同時実行を禁止（in-flight がある間は次フレームをスキップ）
        // 2) 推論投入間隔を制御（約15fps上限）
        let now = CFAbsoluteTimeGetCurrent()
        guard !isInferenceInFlight, now - lastInferenceDispatchTime >= targetInferenceInterval else {
            return
        }

        isInferenceInFlight = true
        lastInferenceDispatchTime = now

        inferenceEngine.infer(sampleBuffer: sampleBuffer, orientation: .right) { [weak self] detections, latency in
            Task { @MainActor in
                guard let self else { return }
                self.isInferenceInFlight = false

                self.latencyMs = latency
                let completionTime = CFAbsoluteTimeGetCurrent()
                if self.lastInferenceCompletionTime > 0 {
                    let delta = completionTime - self.lastInferenceCompletionTime
                    if delta > 0 {
                        let instantaneousFPS = 1.0 / delta
                        // 実測値の揺れを抑えるために軽く平滑化します。
                        self.fps = self.fps == 0 ? instantaneousFPS : (self.fps * 0.7 + instantaneousFPS * 0.3)
                    }
                }
                self.lastInferenceCompletionTime = completionTime

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
