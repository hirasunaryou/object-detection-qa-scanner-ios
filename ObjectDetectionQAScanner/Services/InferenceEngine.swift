import CoreML
import Foundation
import Vision

final class InferenceEngine: ObservableObject {
    private var visionModel: VNCoreMLModel?
    private var request: VNCoreMLRequest?
    private var requestHandler = VNSequenceRequestHandler()
    private var lastFrameTime = CACurrentMediaTime()

    @Published var fps: Double = 0
    @Published var latencyMS: Double = 0

    func load(compiledModelURL: URL) throws {
        let model = try MLModel(contentsOf: compiledModelURL)
        let vnModel = try VNCoreMLModel(for: model)
        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill
        self.visionModel = vnModel
        self.request = request
    }

    func infer(pixelBuffer: CVPixelBuffer) -> [DetectionResult] {
        guard let request else { return [] }
        let started = CACurrentMediaTime()
        do {
            try requestHandler.perform([request], on: pixelBuffer)
        } catch {
            return []
        }

        let now = CACurrentMediaTime()
        latencyMS = (now - started) * 1000
        let delta = now - lastFrameTime
        if delta > 0 { fps = 1.0 / delta }
        lastFrameTime = now

        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        return observations.map {
            DetectionResult(label: $0.labels.first?.identifier ?? "unknown",
                            confidence: Double($0.confidence),
                            boundingBox: $0.boundingBox)
        }
    }
}
