import Foundation
import Vision
import CoreML
import AVFoundation
import os

final class InferenceEngine {
    private var request: VNCoreMLRequest?
    private var modelInputSize: CGSize = .zero
    private var classLabels: [String] = []
    private let queue = DispatchQueue(label: "inference.queue", qos: .userInitiated)
    private let logger = Logger(subsystem: "ObjectDetectionQAScanner", category: "InferenceEngine")
    private(set) var activeModelID: String?
    // Liveプレビューは背面カメラの portrait 固定運用のため、Vision 側も同じ向きで評価する。
    // `.up` を使うとバウンディングボックスの向きがズレるため、`.right` を利用する。
    private let liveOrientation: CGImagePropertyOrientation = .right

    func loadModel(modelID: String, compiledModelURL: URL, classLabels: [String]) throws {
        let model = try MLModel(contentsOf: compiledModelURL)
        let vnModel = try VNCoreMLModel(for: model)

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill

        self.request = request
        self.modelInputSize = Self.resolveModelInputSize(model: model)
        self.classLabels = classLabels
        self.activeModelID = modelID
    }

    func infer(sampleBuffer: CMSampleBuffer, completion: @escaping ([Detection], Double, String) -> Void) {
        guard let request else {
            completion([Detection](), 0, "output=none")
            return
        }

        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: self.liveOrientation)
            do {
                try handler.perform([request])
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                if let observations = request.results as? [VNRecognizedObjectObservation] {
                    let detections: [Detection] = observations.compactMap { obs in
                        guard let top = obs.labels.first else { return nil }
                        return Detection(label: top.identifier, confidence: Double(top.confidence), boundingBox: obs.boundingBox)
                    }
                    self.logger.debug("Inference output type: recognized_object count=\(detections.count)")
                    completion(detections, elapsed, "output=recognized")
                    return
                }

                if let features = request.results as? [VNCoreMLFeatureValueObservation] {
                    let orientedImageSize = Self.resolveOrientedImageSize(sampleBuffer: sampleBuffer, orientation: self.liveOrientation)
                    let decoded = self.decodeYOLOv8Detections(
                        featureObservations: features,
                        orientedImageSize: orientedImageSize,
                        confidenceThreshold: 0.35,
                        iouThreshold: 0.45,
                        maxDetections: 20
                    )
                    self.logger.debug("Inference output type: multiarray info=\(decoded.debugText, privacy: .public)")
                    completion(decoded.detections, elapsed, decoded.debugText)
                    return
                }

                completion([Detection](), elapsed, "output=unknown")
            } catch {
                completion([Detection](), (CFAbsoluteTimeGetCurrent() - start) * 1000, "output=error")
            }
        }
    }

    private func decodeYOLOv8Detections(
        featureObservations: [VNCoreMLFeatureValueObservation],
        orientedImageSize: CGSize,
        confidenceThreshold: Double,
        iouThreshold: Double,
        maxDetections: Int
    ) -> (detections: [Detection], debugText: String) {
        guard let multiArray = featureObservations.compactMap({ $0.featureValue.multiArrayValue }).first else {
            return ([], "output=multiarray shape=n/a")
        }

        // YOLOv8 の出力は [1,C,N] または [1,N,C] のどちらでも来るため、shape から軸順を推定する。
        let shape = multiArray.shape.map { $0.intValue }
        guard let layout = Self.inferTensorLayout(shape: shape, classCount: classLabels.count) else {
            return ([], "output=multiarray shape=\(shape) layout=unsupported")
        }

        let numClasses = max(layout.channels - 4, 0)
        var candidates: [Detection] = []
        candidates.reserveCapacity(layout.boxes)

        for boxIndex in 0..<layout.boxes {
            let x = Self.value(at: boxIndex, channel: 0, in: multiArray, layout: layout)
            let y = Self.value(at: boxIndex, channel: 1, in: multiArray, layout: layout)
            let w = Self.value(at: boxIndex, channel: 2, in: multiArray, layout: layout)
            let h = Self.value(at: boxIndex, channel: 3, in: multiArray, layout: layout)

            if w <= 0 || h <= 0 { continue }

            var bestClass = 0
            var bestScore = -Double.infinity
            for classIndex in 0..<numClasses {
                let score = Self.value(at: boxIndex, channel: 4 + classIndex, in: multiArray, layout: layout)
                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }

            guard bestScore >= confidenceThreshold else { continue }

            let label: String
            if classLabels.indices.contains(bestClass) {
                label = classLabels[bestClass]
            } else {
                label = "class_\(bestClass)"
            }

            let modelSquare = max(max(Double(modelInputSize.width), Double(modelInputSize.height)), 1)
            let rectInModel = CGRect(
                x: x - (w / 2),
                y: y - (h / 2),
                width: w,
                height: h
            )

            // 出力の xywh はモデル入力座標系（通常 640x640 などの正方形）なので、まず正規化する。
            let normalizedSquare = CGRect(
                x: rectInModel.origin.x / modelSquare,
                y: rectInModel.origin.y / modelSquare,
                width: rectInModel.width / modelSquare,
                height: rectInModel.height / modelSquare
            )

            // Vision の .scaleFill で発生する中央クロップを逆変換して、元フレーム正規化座標へ戻す。
            let mapped = Self.remapScaleFillRectToVisionNormalized(
                normalizedSquareRect: normalizedSquare,
                sourceImageSize: orientedImageSize,
                modelSquareSize: modelSquare
            )

            guard mapped.width > 0, mapped.height > 0 else { continue }
            candidates.append(Detection(label: label, confidence: bestScore, boundingBox: mapped))
        }

        let nms = Self.nonMaximumSuppression(candidates, iouThreshold: iouThreshold, maxDetections: maxDetections)
        return (nms, "output=multiarray shape=\(shape) layout=\(layout.debugDescription)")
    }

    private static func resolveModelInputSize(model: MLModel) -> CGSize {
        for description in model.modelDescription.inputDescriptionsByName.values {
            if let constraint = description.imageConstraint {
                return CGSize(width: constraint.pixelsWide, height: constraint.pixelsHigh)
            }
        }
        return CGSize(width: 640, height: 640)
    }

    private static func resolveOrientedImageSize(sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation) -> CGSize {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return CGSize(width: 1, height: 1)
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }

    private static func remapScaleFillRectToVisionNormalized(
        normalizedSquareRect: CGRect,
        sourceImageSize: CGSize,
        modelSquareSize: Double
    ) -> CGRect {
        let sourceWidth = max(Double(sourceImageSize.width), 1)
        let sourceHeight = max(Double(sourceImageSize.height), 1)
        let scale = max(modelSquareSize / sourceWidth, modelSquareSize / sourceHeight)
        let scaledWidth = sourceWidth * scale
        let scaledHeight = sourceHeight * scale
        let cropX = (scaledWidth - modelSquareSize) / 2
        let cropY = (scaledHeight - modelSquareSize) / 2

        let x = ((Double(normalizedSquareRect.origin.x) * modelSquareSize + cropX) / scale) / sourceWidth
        let y = ((Double(normalizedSquareRect.origin.y) * modelSquareSize + cropY) / scale) / sourceHeight
        let w = ((Double(normalizedSquareRect.width) * modelSquareSize) / scale) / sourceWidth
        let h = ((Double(normalizedSquareRect.height) * modelSquareSize) / scale) / sourceHeight

        let rect = CGRect(x: x, y: y, width: w, height: h)
        return rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func nonMaximumSuppression(_ detections: [Detection], iouThreshold: Double, maxDetections: Int) -> [Detection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var selected: [Detection] = []
        for candidate in sorted {
            if selected.count >= maxDetections { break }
            let overlaps = selected.contains { iou($0.boundingBox, candidate.boundingBox) > iouThreshold }
            if !overlaps {
                selected.append(candidate)
            }
        }
        return selected
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        if inter.isNull || inter.width <= 0 || inter.height <= 0 { return 0 }
        let interArea = inter.width * inter.height
        let unionArea = a.width * a.height + b.width * b.height - interArea
        if unionArea <= 0 { return 0 }
        return Double(interArea / unionArea)
    }

    private struct TensorLayout {
        let channels: Int
        let boxes: Int
        let channelsFirst: Bool
        let rank: Int

        var debugDescription: String {
            channelsFirst ? "[1,C,N]" : "[1,N,C]"
        }
    }

    private static func inferTensorLayout(shape: [Int], classCount: Int) -> TensorLayout? {
        guard shape.count >= 2 else { return nil }
        let rank = shape.count
        let channelsCandidateA = shape[shape.count - 2]
        let channelsCandidateB = shape[shape.count - 1]
        let targetChannels = classCount > 0 ? 4 + classCount : -1

        if targetChannels > 0 {
            if channelsCandidateA == targetChannels {
                return TensorLayout(channels: channelsCandidateA, boxes: channelsCandidateB, channelsFirst: true, rank: rank)
            }
            if channelsCandidateB == targetChannels {
                return TensorLayout(channels: channelsCandidateB, boxes: channelsCandidateA, channelsFirst: false, rank: rank)
            }
        }

        if channelsCandidateA < channelsCandidateB {
            return TensorLayout(channels: channelsCandidateA, boxes: channelsCandidateB, channelsFirst: true, rank: rank)
        }
        return TensorLayout(channels: channelsCandidateB, boxes: channelsCandidateA, channelsFirst: false, rank: rank)
    }

    private static func value(at box: Int, channel: Int, in array: MLMultiArray, layout: TensorLayout) -> Double {
        let strides = array.strides.map { $0.intValue }
        let shape = array.shape.map { $0.intValue }
        var index = Array(repeating: 0, count: layout.rank)
        if layout.rank >= 3 {
            let secondAxis = layout.rank - 2
            let thirdAxis = layout.rank - 1
            if layout.channelsFirst {
                index[secondAxis] = channel
                index[thirdAxis] = box
            } else {
                index[secondAxis] = box
                index[thirdAxis] = channel
            }
        } else if shape.count == 2 {
            if layout.channelsFirst {
                index[0] = channel
                index[1] = box
            } else {
                index[0] = box
                index[1] = channel
            }
        }

        var linear = 0
        for axis in 0..<index.count {
            linear += index[axis] * strides[axis]
        }
        return array[linear].doubleValue
    }
}
