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

    func infer(sampleBuffer: CMSampleBuffer, completion: @escaping ([Detection], Double) -> Void) {
        guard let request else {
            completion([], 0)
            return
        }

        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
            do {
                try handler.perform([request])
                let detections = (request.results as? [VNRecognizedObjectObservation])?.compactMap { obs in
                    guard let top = obs.labels.first else { return nil }
                    return Detection(label: top.identifier, confidence: Double(top.confidence), boundingBox: obs.boundingBox)
                } ?? []
                completion(detections, (CFAbsoluteTimeGetCurrent() - start) * 1000)
            } catch {
                completion([], (CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
        }
    }
}
