import Foundation
import Vision
import CoreML
import AVFoundation

final class InferenceEngine {
    private var request: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "inference.queue", qos: .userInitiated)
    private(set) var activeModelID: String?

    func loadModel(modelID: String, compiledModelURL: URL) throws {
        let model = try MLModel(contentsOf: compiledModelURL)
        let vnModel = try VNCoreMLModel(for: model)

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill

        self.request = request
        self.activeModelID = modelID
    }

    // NOTE:
    // Visionへ渡すorientationは検出結果の座標系にも影響します。
    // バックカメラ + portrait運用では .right を使うことで、
    // 推論結果の正規化座標をプレビューの見た目と合わせやすくなります。
    func infer(
        sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation = .right,
        completion: @escaping ([Detection], Double) -> Void
    ) {
        guard let request else {
            completion([Detection](), 0)
            return
        }

        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation)
            do {
                try handler.perform([request])
                // NOTE: `[]` が [Any] と推論されるのを避けるため、型を明示します。
                let detections: [Detection] = (request.results as? [VNRecognizedObjectObservation])?.compactMap { obs in
                    guard let top = obs.labels.first else { return nil }
                    return Detection(label: top.identifier, confidence: Double(top.confidence), boundingBox: obs.boundingBox)
                } ?? [Detection]()
                completion(detections, (CFAbsoluteTimeGetCurrent() - start) * 1000)
            } catch {
                completion([Detection](), (CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
        }
    }
}
