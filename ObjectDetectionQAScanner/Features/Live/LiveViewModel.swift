import AVFoundation
import SwiftUI
import UIKit

@MainActor
/// Live画面の制御。カメラ→推論→安定判定→ログ保存をつなぐ。
final class LiveViewModel: ObservableObject {
    @Published var detections: [DetectionResult] = []
    @Published var stableState = FrameStabilityState(isStable: false, stableFrameCount: 0, flickerCount: 0)
    @Published var currentImage: UIImage?
    @Published var infoText = "モデルを選択してください"

    let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        setupCameraPipeline()
    }

    var fpsText: String { String(format: "FPS %.1f", container.inferenceEngine.fps) }
    var latencyText: String { String(format: "Latency %.1f ms", container.inferenceEngine.latencyMS) }

    func onAppear() {
        requestCameraPermission()
        loadActiveModel()
    }

    func onDisappear() {
        container.cameraManager.stop()
    }

    func confirmOpen() {
        saveLog(status: "success", reason: nil)
        container.stabilityEvaluator.reset()
    }

    func markNG(reason: NGReason) {
        saveLog(status: "ng", reason: reason.rawValue)
        container.stabilityEvaluator.reset()
    }

    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted { self.container.cameraManager.start() }
        }
    }

    private func setupCameraPipeline() {
        container.cameraManager.onFrame = { [weak self] sampleBuffer in
            guard let self else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let inferenceResults = self.container.inferenceEngine.infer(pixelBuffer: pixelBuffer)
            Task { @MainActor in
                self.detections = inferenceResults
                self.stableState = self.container.stabilityEvaluator.evaluate(
                    detections: inferenceResults,
                    settings: self.container.modelRegistry.settings
                )
                self.currentImage = sampleBuffer.toUIImage()
                self.infoText = self.stableState.isStable ? "stable" : "stabilizing (\(self.stableState.stableFrameCount))"
            }
        }
    }

    private func loadActiveModel() {
        guard let model = container.modelRegistry.activeModel else {
            infoText = "Modelsタブでモデルをインポートしてください"
            return
        }
        do {
            try container.inferenceEngine.load(compiledModelURL: URL(fileURLWithPath: model.compiledModelPath))
            infoText = "\(model.manifest.displayName) loaded"
        } catch {
            infoText = "モデルロード失敗: \(error.localizedDescription)"
        }
    }

    private func saveLog(status: String, reason: String?) {
        guard let model = container.modelRegistry.activeModel else { return }
        guard let image = currentImage else { return }

        let imageFile = container.logStore.saveImage(image, prefix: status)
        let entry = ScanLogEntry(
            id: UUID(),
            timestamp: Date(),
            modelID: model.id,
            modelName: model.manifest.displayName,
            status: status,
            reason: reason,
            latencyMS: container.inferenceEngine.latencyMS,
            fps: container.inferenceEngine.fps,
            timeToStableMS: container.stabilityEvaluator.elapsedToStableMS(),
            flickerCount: stableState.flickerCount,
            detectionCount: detections.count,
            labels: detections.map(\.label),
            imageFilename: imageFile
        )
        container.logStore.append(entry)
    }
}

private extension CMSampleBuffer {
    func toUIImage() -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
