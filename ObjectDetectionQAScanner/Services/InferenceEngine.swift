import Foundation
import Vision
import CoreML
import AVFoundation

final class InferenceEngine {
    private var request: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "inference.queue", qos: .userInitiated)
    private(set) var activeModelID: String?
    // Liveプレビューは背面カメラの portrait 固定運用のため、Vision 側も同じ向きで評価する。
    // `.up` を使うとバウンディングボックスの向きがズレるため、`.right` を利用する。
    private let liveOrientation: CGImagePropertyOrientation = .right

    func loadModel(modelID: String, compiledModelURL: URL) throws {
        let model = try MLModel(contentsOf: compiledModelURL)
        let vnModel = try VNCoreMLModel(for: model)

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill

        self.request = request
        self.activeModelID = modelID
    }

    func infer(sampleBuffer: CMSampleBuffer, completion: @escaping ([Detection], Double) -> Void) {
        guard let request else {
            completion([Detection](), 0)
            return
        }

        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: self.liveOrientation)
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
