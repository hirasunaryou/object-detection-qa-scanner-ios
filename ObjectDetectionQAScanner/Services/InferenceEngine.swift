import Foundation
import Vision
import CoreML
import AVFoundation
import CoreGraphics

final class InferenceEngine {
    struct InferenceDebugInfo {
        let outputType: String
        let multiArrayShape: String?
        let decodedCandidates: Int?
        let afterNMS: Int?
        let sampleBoundingBoxText: String?

        var summaryText: String {
            var parts: [String] = []
            if let multiArrayShape {
                parts.append("Output: \(outputType) (shape: \(multiArrayShape))")
            } else {
                parts.append("Output: \(outputType)")
            }

            if let decodedCandidates {
                parts.append("decodedCandidates: \(decodedCandidates)")
            }
            if let afterNMS {
                parts.append("afterNMS: \(afterNMS)")
            }
            if let sampleBoundingBoxText {
                parts.append("sampleBBox: \(sampleBoundingBoxText)")
            }
            return parts.joined(separator: "\n")
        }
    }

    private var request: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "inference.queue", qos: .userInitiated)
    private(set) var activeModelID: String?
    private var classLabels: [String] = []
    private var modelInputSize: CGSize = CGSize(width: 640, height: 640)

    private let yoloIouThreshold: Double = 0.45
    private let yoloMaxDetections: Int = 20
    // Liveプレビューは背面カメラの portrait 固定運用のため、Vision 側も同じ向きで評価する。
    // `.up` を使うとバウンディングボックスの向きがズレるため、`.right` を利用する。
    private let liveOrientation: CGImagePropertyOrientation = .right

    func loadModel(modelID: String, compiledModelURL: URL, classLabels: [String]) throws {
        let model = try MLModel(contentsOf: compiledModelURL)
        let vnModel = try VNCoreMLModel(for: model)

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill

        self.request = request
        self.activeModelID = modelID
        self.classLabels = classLabels

        if let imageInput = model.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .image }),
           let constraint = imageInput.imageConstraint {
            self.modelInputSize = CGSize(width: constraint.pixelsWide, height: constraint.pixelsHigh)
        }
    }

    func infer(
        sampleBuffer: CMSampleBuffer,
        confidenceThreshold: Double,
        completion: @escaping ([Detection], Double, InferenceDebugInfo) -> Void
    ) {
        guard let request else {
            completion([Detection](), 0, InferenceDebugInfo(outputType: "none", multiArrayShape: nil, decodedCandidates: nil, afterNMS: nil, sampleBoundingBoxText: nil))
            return
        }

        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: self.liveOrientation)
            do {
                try handler.perform([request])
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

                if let observations = request.results as? [VNRecognizedObjectObservation] {
                    // NOTE: `[]` が [Any] と推論されるのを避けるため、型を明示します。
                    let detections: [Detection] = observations.compactMap { obs in
                        guard let top = obs.labels.first else { return nil }
                        return Detection(label: top.identifier, confidence: Double(top.confidence), boundingBox: obs.boundingBox)
                    }
                    completion(detections, elapsedMs, InferenceDebugInfo(outputType: "recognized", multiArrayShape: nil, decodedCandidates: nil, afterNMS: nil, sampleBoundingBoxText: nil))
                    return
                }

                if let featureObservations = request.results as? [VNCoreMLFeatureValueObservation],
                   let firstMultiArray = featureObservations.compactMap({ $0.featureValue.multiArrayValue }).first {
                    let orientedSize = self.orientedImageSize(from: sampleBuffer)
                    let decoded = self.decodeYOLOv8(
                        multiArray: firstMultiArray,
                        imageSize: orientedSize,
                        modelInputSize: self.modelInputSize,
                        confidenceThreshold: confidenceThreshold
                    )
                    let shapeDescription = firstMultiArray.shape.map { String(describing: $0) }.joined(separator: "x")
                    completion(decoded.detections, elapsedMs, InferenceDebugInfo(
                        outputType: "multiarray",
                        multiArrayShape: shapeDescription,
                        decodedCandidates: decoded.decodedCandidates,
                        afterNMS: decoded.afterNMS,
                        sampleBoundingBoxText: decoded.sampleBoundingBoxText
                    ))
                    return
                }

                completion([Detection](), elapsedMs, InferenceDebugInfo(outputType: "unknown", multiArrayShape: nil, decodedCandidates: nil, afterNMS: nil, sampleBoundingBoxText: nil))
            } catch {
                completion([Detection](), (CFAbsoluteTimeGetCurrent() - start) * 1000, InferenceDebugInfo(outputType: "error", multiArrayShape: nil, decodedCandidates: nil, afterNMS: nil, sampleBoundingBoxText: nil))
            }
        }
    }

    private struct YOLODecodeResult {
        let detections: [Detection]
        let decodedCandidates: Int
        let afterNMS: Int
        let sampleBoundingBoxText: String?
    }

    // YOLOv8 の生出力(4+numClasses, boxes)を [Detection] へ変換する。
    // - 좌標系: モデル出力は左上原点想定のため、Vision 用(左下原点)へY軸反転する。
    // - `.scaleFill`: 正方形入力へ伸縮された座標を、明示的に元画像サイズに戻してから正規化する。
    private func decodeYOLOv8(
        multiArray: MLMultiArray,
        imageSize: CGSize,
        modelInputSize: CGSize,
        confidenceThreshold: Double
    ) -> YOLODecodeResult {
        let shape = multiArray.shape.map { Int(truncating: $0) }
        guard shape.count == 3 else {
            return YOLODecodeResult(detections: [], decodedCandidates: 0, afterNMS: 0, sampleBoundingBoxText: nil)
        }

        let dim1 = shape[1]
        let dim2 = shape[2]

        // YOLOv8 出力は通常 [1, channels, boxes]。
        // channels は 4+classCount (objectness ありモデルは 5+classCount) を期待する。
        let expectedChannels = 4 + classLabels.count
        let expectedChannelsWithObjectness = 5 + classLabels.count

        let channels: Int
        let boxCount: Int
        let channelsFirst: Bool
        if dim1 == expectedChannels || dim1 == expectedChannelsWithObjectness {
            channels = dim1
            boxCount = dim2
            channelsFirst = true
        } else if dim2 == expectedChannels || dim2 == expectedChannelsWithObjectness {
            channels = dim2
            boxCount = dim1
            channelsFirst = false
        } else if dim1 < dim2 {
            // 期待形状と合わない場合は [1,channels,boxes] を優先し、より小さい次元を channels とみなす。
            channels = dim1
            boxCount = dim2
            channelsFirst = true
        } else {
            channels = dim2
            boxCount = dim1
            channelsFirst = false
        }

        guard channels >= 5, boxCount > 0 else {
            return YOLODecodeResult(detections: [], decodedCandidates: 0, afterNMS: 0, sampleBoundingBoxText: nil)
        }
        let hasObjectness = channels == expectedChannelsWithObjectness
        let classOffset = hasObjectness ? 5 : 4
        let classCount = channels - classOffset
        guard classCount > 0 else {
            return YOLODecodeResult(detections: [], decodedCandidates: 0, afterNMS: 0, sampleBoundingBoxText: nil)
        }

        let strides = multiArray.strides.map { Int(truncating: $0) }

        func valueAt(channel: Int, box: Int) -> Double {
            // shape が [1,C,N] の場合と [1,N,C] の場合の双方を扱う。
            let index: Int
            if channelsFirst {
                index = channel * strides[1] + box * strides[2]
            } else {
                index = box * strides[1] + channel * strides[2]
            }

            switch multiArray.dataType {
            case .double:
                let ptr = multiArray.dataPointer.bindMemory(to: Double.self, capacity: multiArray.count)
                return ptr[index]
            case .float32:
                let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
                return Double(ptr[index])
            case .float16:
                let ptr = multiArray.dataPointer.bindMemory(to: UInt16.self, capacity: multiArray.count)
                return Double(Float16(bitPattern: ptr[index]))
            default:
                return 0
            }
        }

        var candidates: [Detection] = []
        candidates.reserveCapacity(min(boxCount, 200))

        for boxIndex in 0..<boxCount {
            var centerX = valueAt(channel: 0, box: boxIndex)
            var centerY = valueAt(channel: 1, box: boxIndex)
            var width = valueAt(channel: 2, box: boxIndex)
            var height = valueAt(channel: 3, box: boxIndex)

            // 座標値が小さい場合は 0...1 正規化とみなし、モデル入力サイズへ戻す。
            let maxCoordinate = max(centerX, centerY, width, height)
            if maxCoordinate <= 2.0 {
                centerX *= modelInputSize.width
                centerY *= modelInputSize.height
                width *= modelInputSize.width
                height *= modelInputSize.height
            }

            var bestClass = 0
            var bestScore = -Double.infinity
            for classIndex in 0..<classCount {
                let score = valueAt(channel: classOffset + classIndex, box: boxIndex)
                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }

            if hasObjectness {
                let objectness = valueAt(channel: 4, box: boxIndex)
                bestScore *= objectness
            }

            guard bestScore >= confidenceThreshold else { continue }

            let left = centerX - (width / 2.0)
            let top = centerY - (height / 2.0)

            // `.scaleFill` でモデル入力(多くは正方形)へ変換された座標を、元の向き付き画像へ戻す。
            let mappedRect = mapScaleFillRectToImage(
                x: left,
                y: top,
                width: width,
                height: height,
                imageSize: imageSize,
                modelInputSize: modelInputSize
            )
            guard mappedRect.width > 0, mappedRect.height > 0 else { continue }

            // Vision の normalizedRect は左下原点なので、上原点のyを反転する。
            let normalizedX = mappedRect.minX / imageSize.width
            let normalizedY = 1.0 - ((mappedRect.minY + mappedRect.height) / imageSize.height)
            let normalizedW = mappedRect.width / imageSize.width
            let normalizedH = mappedRect.height / imageSize.height

            let normalizedRect = CGRect(
                x: normalizedX,
                y: normalizedY,
                width: normalizedW,
                height: normalizedH
            ).standardized
            let clamped = clampNormalizedRect(normalizedRect)
            guard clamped.width > 0, clamped.height > 0 else { continue }

            let label = classLabels.indices.contains(bestClass) ? classLabels[bestClass] : "class_\(bestClass)"
            candidates.append(Detection(label: label, confidence: bestScore, boundingBox: clamped))
        }

        let nms = nonMaximumSuppression(candidates, iouThreshold: yoloIouThreshold)
        let finalDetections = Array(nms.prefix(yoloMaxDetections))
        let sampleText = finalDetections.first.map {
            String(
                format: "x: %.3f y: %.3f w: %.3f h: %.3f",
                $0.boundingBox.minX,
                $0.boundingBox.minY,
                $0.boundingBox.width,
                $0.boundingBox.height
            )
        }
        return YOLODecodeResult(
            detections: finalDetections,
            decodedCandidates: candidates.count,
            afterNMS: nms.count,
            sampleBoundingBoxText: sampleText
        )
    }

    private func orientedImageSize(from sampleBuffer: CMSampleBuffer) -> CGSize {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return CGSize(width: 1, height: 1)
        }
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        // `.right` で評価しているため portrait 基準へ揃える。
        return CGSize(width: height, height: width)
    }

    private func mapScaleFillRectToImage(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        imageSize: CGSize,
        modelInputSize: CGSize
    ) -> CGRect {
        let modelW = max(modelInputSize.width, 1)
        let modelH = max(modelInputSize.height, 1)
        let scaleX = imageSize.width / modelW
        let scaleY = imageSize.height / modelH

        return CGRect(
            x: x * scaleX,
            y: y * scaleY,
            width: width * scaleX,
            height: height * scaleY
        )
    }

    private func clampNormalizedRect(_ rect: CGRect) -> CGRect {
        let x = max(0, min(1, rect.origin.x))
        let y = max(0, min(1, rect.origin.y))
        let maxX = max(x, min(1, rect.maxX))
        let maxY = max(y, min(1, rect.maxY))
        return CGRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    private func nonMaximumSuppression(_ detections: [Detection], iouThreshold: Double) -> [Detection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var selected: [Detection] = []

        for candidate in sorted {
            let shouldKeep = selected.allSatisfy { kept in
                iou(candidate.boundingBox, kept.boundingBox) < iouThreshold
            }
            if shouldKeep {
                selected.append(candidate)
            }
        }
        return selected
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = Double(intersection.width * intersection.height)
        let unionArea = Double(a.width * a.height + b.width * b.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
