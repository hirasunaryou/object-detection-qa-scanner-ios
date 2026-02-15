import Foundation
import Combine
import AVFoundation

@MainActor
// Live画面のオーケストレーター。
// カメラ -> 推論 -> 安定判定 -> UI更新/ログ保存 までを1つの責務として管理する。
final class LiveViewModel: ObservableObject {
    enum SaveError: LocalizedError {
        case noCapturedFrame
        case noActiveModel

        var errorDescription: String? {
            switch self {
            case .noCapturedFrame:
                return "画像フレームがまだ取得できていません。"
            case .noActiveModel:
                return "モデルが読み込まれていないため保存できません。"
            }
        }
    }
    @Published var detections: [Detection] = []
    @Published var isStable = false
    @Published var stableReason = ""
    @Published var fps: Double = 0
    @Published var latencyMs: Double = 0
    @Published var flickerCount: Int = 0
    @Published var latestFrame: CMSampleBuffer?
    @Published var secondsToStable: Double?
    @Published var modelStatusText: String = "No model loaded"
    @Published var inferenceImageSize: CGSize = .zero
    @Published var inferenceDebugText: String = "Output: -"
    @Published var orientationDebugText: String = "orientation: -"

    let cameraManager: CameraManager
    private let inferenceEngine: InferenceEngine
    private let stabilityEvaluator = StabilityEvaluator()
    private let logStore: LogStore
    private var settingsStore: SettingsStore
    private var activeModelProvider: () -> StoredModel?

    private var isInferenceInFlight = false
    private var lastInferenceStart = Date.distantPast
    private var lastInferenceCompletion = Date.distantPast
    // 保存時に「検出結果と同じ入力フレーム」を使うため、
    // 推論完了時点の sampleBuffer を保持する（最新カメラフレームとは分ける）。
    private var lastInferenceFrame: CMSampleBuffer?
    private var lastInferenceExifOrientation: CGImagePropertyOrientation = .right
    private let targetInferenceInterval: TimeInterval = 1.0 / 14.0

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

        cameraManager.onFrame = { [weak self] sampleBuffer, videoOrientation, isMirrored in
            Task { await self?.handleFrame(sampleBuffer, videoOrientation: videoOrientation, isMirrored: isMirrored) }
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
        try inferenceEngine.loadModel(
            modelID: model.id,
            compiledModelURL: modelStore.compiledURL(for: model),
            classLabels: model.metadata.classes
        )
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
        guard let model = activeModelProvider() else {
            throw SaveError.noActiveModel
        }
        // 直近のカメラ受信フレームではなく、現在の detections を算出したフレームを保存する。
        guard let frame = lastInferenceFrame else {
            throw SaveError.noCapturedFrame
        }

        // 画面で調整した安定判定パラメータを、その時点のスナップショットとしてログへ残す。
        let settingsSnapshot = settingsStore.settings

        _ = try logStore.saveScan(
            modelID: model.id,
            action: action,
            ngReason: reason,
            stabilitySettings: settingsSnapshot,
            isStable: isStable,
            latencyMs: latencyMs,
            fps: fps,
            detections: detections,
            flickerCount: flickerCount,
            secondsToStable: secondsToStable,
            sampleBuffer: frame,
            exifOrientation: lastInferenceExifOrientation
        )
        resetStabilityState()
    }

    private func handleFrame(
        _ sampleBuffer: CMSampleBuffer,
        videoOrientation: AVCaptureVideoOrientation,
        isMirrored: Bool
    ) async {
        latestFrame = sampleBuffer
        if inferenceEngine.activeModelID == nil {
            detections = []
            isStable = false
            stableReason = "no_model"
            return
        }

        // 1) 推論は常に1本だけ実行する。
        // 2) 実行開始間隔を最短 ~71ms (約14fps) に制限して、負荷スパイクと遅延蓄積を抑える。
        let now = Date()
        guard !isInferenceInFlight else { return }
        guard now.timeIntervalSince(lastInferenceStart) >= targetInferenceInterval else { return }

        isInferenceInFlight = true
        lastInferenceStart = now

        let exifOrientation = OrientationResolver.exifOrientation(videoOrientation: videoOrientation, isMirrored: isMirrored)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isInferenceInFlight = false
            return
        }
        let pixelBufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let pixelBufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        let orientedImageSize = OrientationResolver.orientedImageSize(
            pixelBufferWidth: pixelBufferWidth,
            pixelBufferHeight: pixelBufferHeight,
            exifOrientation: exifOrientation
        )
        inferenceImageSize = orientedImageSize
        orientationDebugText = Self.orientationDebugDescription(
            videoOrientation: videoOrientation,
            isMirrored: isMirrored,
            exifOrientation: exifOrientation,
            pixelBufferWidth: pixelBufferWidth,
            pixelBufferHeight: pixelBufferHeight,
            orientedImageSize: orientedImageSize
        )

        inferenceEngine.infer(
            sampleBuffer: sampleBuffer,
            orientation: exifOrientation,
            orientedImageSize: orientedImageSize,
            confidenceThreshold: settingsStore.settings.confThreshold
        ) { [weak self] detections, latency, debugInfo in
            Task { @MainActor in
                guard let self else { return }
                self.isInferenceInFlight = false

                let completedAt = Date()
                let fpsDelta = completedAt.timeIntervalSince(self.lastInferenceCompletion)
                self.lastInferenceCompletion = completedAt
                if fpsDelta > 0 {
                    self.fps = 1.0 / fpsDelta
                }

                self.latencyMs = latency
                self.detections = detections
                self.inferenceDebugText = debugInfo.summaryText
                // detections と 1:1 で対応するフレームを更新する。
                // ここで更新しておけば、保存時に画像と検出結果のズレが発生しない。
                self.lastInferenceFrame = sampleBuffer
                self.lastInferenceExifOrientation = exifOrientation

                let result = self.stabilityEvaluator.evaluate(detections: detections, settings: self.settingsStore.settings)
                self.isStable = result.isStable
                self.stableReason = result.reason
                self.flickerCount = result.flickerCount
                self.secondsToStable = result.secondsToStable
            }
        }
    }

    private static func orientationDebugDescription(
        videoOrientation: AVCaptureVideoOrientation,
        isMirrored: Bool,
        exifOrientation: CGImagePropertyOrientation,
        pixelBufferWidth: Int,
        pixelBufferHeight: Int,
        orientedImageSize: CGSize
    ) -> String {
        "videoOrientation: \(videoOrientation.debugName) | isMirrored: \(isMirrored) | exifOrientation: \(exifOrientation.debugName) | pixelBuffer: \(pixelBufferWidth)x\(pixelBufferHeight) | orientedImageSize: \(Int(orientedImageSize.width))x\(Int(orientedImageSize.height))"
    }
}

private extension AVCaptureVideoOrientation {
    var debugName: String {
        switch self {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeRight: return "landscapeRight"
        case .landscapeLeft: return "landscapeLeft"
        @unknown default: return "unknown"
        }
    }
}

private extension CGImagePropertyOrientation {
    var debugName: String {
        switch self {
        case .up: return "up"
        case .upMirrored: return "upMirrored"
        case .down: return "down"
        case .downMirrored: return "downMirrored"
        case .left: return "left"
        case .leftMirrored: return "leftMirrored"
        case .right: return "right"
        case .rightMirrored: return "rightMirrored"
        @unknown default: return "unknown"
        }
    }
}
