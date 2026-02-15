import Foundation
import Vision
import CoreML
import AVFoundation
import CoreGraphics

final class InferenceEngine {
    struct InferenceDebugInfo {
        let outputType: String
        let preprocessMode: String?
        let multiArrayShape: String?
        let decodedCandidatesCount: Int?
        let afterNMSCount: Int?
        let sampleBBoxText: String?
        let sampleMappedRectText: String?

        var summaryText: String {
            var parts: [String] = []
            if let multiArrayShape {
                parts.append("Output: \(outputType) (shape: \(multiArrayShape))")
            } else {
                parts.append("Output: \(outputType)")
            }

            if let decodedCandidatesCount {
                parts.append("decodedCandidates: \(decodedCandidatesCount)")
            }
            if let afterNMSCount {
                parts.append("afterNMS: \(afterNMSCount)")
            }
            if let preprocessMode {
                parts.append("preprocess: \(preprocessMode)")
            }
            if let sampleMappedRectText {
                parts.append("mappedRect(px): \(sampleMappedRectText)")
            }
            if let sampleBBoxText {
                parts.append("sampleBBox: \(sampleBBoxText)")
            }

            return parts.joined(separator: " | ")
        }
    }

    private struct YOLODecodeOutput {
        let detections: [Detection]
        let decodedCandidatesCount: Int
        let afterNMSCount: Int
        let sampleBBoxText: String?
        let sampleMappedRectText: String?
    }

    private var request: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "inference.queue", qos: .userInitiated)
    private(set) var activeModelID: String?
    private var classLabels: [String] = []
    private var modelInputSize: CGSize = CGSize(width: 640, height: 640)
    private let debugLogStore: DebugLogStore

    private let yoloIouThreshold: Double = 0.45
    private let yoloMaxDetections: Int = 20
    init(debugLogStore: DebugLogStore = .shared) {
        self.debugLogStore = debugLogStore
    }

    func loadModel(modelID: String, compiledModelURL: URL, classLabels: [String]) throws {
        let model = try MLModel(contentsOf: compiledModelURL)
        let vnModel = try VNCoreMLModel(for: model)

        let request = VNCoreMLRequest(model: vnModel)
        // YOLO の letterbox 前処理と一致させるため、アスペクト比を保った scaleFit を使う。
        request.imageCropAndScaleOption = .scaleFit

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
        orientation: CGImagePropertyOrientation,
        orientedImageSize: CGSize,
        confidenceThreshold: Double,
        completion: @escaping ([Detection], Double, InferenceDebugInfo) -> Void
    ) {
        guard let request else {
            debugLogStore.warn(tag: "InferenceEngine", message: "infer_skipped_no_model", fields: [:])
            completion([Detection](), 0, InferenceDebugInfo(outputType: "none", preprocessMode: nil, multiArrayShape: nil, decodedCandidatesCount: nil, afterNMSCount: nil, sampleBBoxText: nil, sampleMappedRectText: nil))
            return
        }

        queue.async {
            let start = CFAbsoluteTimeGetCurrent()
            let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: orientation)
            do {
                try handler.perform([request])
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000

                if let observations = request.results as? [VNRecognizedObjectObservation] {
                    // NOTE: `[]` が [Any] と推論されるのを避けるため、型を明示します。
                    let detections: [Detection] = observations.compactMap { obs in
                        guard let top = obs.labels.first else { return nil }
                        return Detection(label: top.identifier, confidence: Double(top.confidence), boundingBox: obs.boundingBox)
                    }
                    self.debugLogStore.info(
                        tag: "InferenceEngine",
                        message: "infer_result",
                        fields: [
                            "output_type": "recognized",
                            "preprocess_mode": "vision_default",
                            "detections_count": detections.count
                        ]
                    )
                    completion(detections, elapsedMs, InferenceDebugInfo(outputType: "recognized", preprocessMode: nil, multiArrayShape: nil, decodedCandidatesCount: nil, afterNMSCount: nil, sampleBBoxText: nil, sampleMappedRectText: nil))
                    return
                }

                if let featureObservations = request.results as? [VNCoreMLFeatureValueObservation],
                   let firstMultiArray = featureObservations.compactMap({ $0.featureValue.multiArrayValue }).first {
                    let decoded = self.decodeYOLOv8(
                        multiArray: firstMultiArray,
                        imageSize: orientedImageSize,
                        modelInputSize: self.modelInputSize,
                        confidenceThreshold: confidenceThreshold
                    )
                    let shapeDescription = firstMultiArray.shape.map { String(describing: $0) }.joined(separator: "x")
                    self.debugLogStore.info(
                        tag: "InferenceEngine",
                        message: "infer_result",
                        fields: [
                            "output_type": "multiarray",
                            "preprocess_mode": "scaleFit",
                            "multiarray_shape": shapeDescription,
                            "decoded_candidates": decoded.decodedCandidatesCount,
                            "after_nms": decoded.afterNMSCount
                        ]
                    )
                    completion(
                        decoded.detections,
                        elapsedMs,
                        InferenceDebugInfo(
                            outputType: "multiarray",
                            preprocessMode: "scaleFit",
                            multiArrayShape: shapeDescription,
                            decodedCandidatesCount: decoded.decodedCandidatesCount,
                            afterNMSCount: decoded.afterNMSCount,
                            sampleBBoxText: decoded.sampleBBoxText,
                            sampleMappedRectText: decoded.sampleMappedRectText
                        )
                    )
                    return
                }

                self.debugLogStore.warn(tag: "InferenceEngine", message: "infer_result_unknown", fields: ["preprocess_mode": "scaleFit"])
                completion([Detection](), elapsedMs, InferenceDebugInfo(outputType: "unknown", preprocessMode: nil, multiArrayShape: nil, decodedCandidatesCount: nil, afterNMSCount: nil, sampleBBoxText: nil, sampleMappedRectText: nil))
            } catch {
                self.debugLogStore.error(tag: "InferenceEngine", message: "infer_error", fields: ["error": error.localizedDescription])
                completion([Detection](), (CFAbsoluteTimeGetCurrent() - start) * 1000, InferenceDebugInfo(outputType: "error: \(error.localizedDescription)", preprocessMode: nil, multiArrayShape: nil, decodedCandidatesCount: nil, afterNMSCount: nil, sampleBBoxText: nil, sampleMappedRectText: nil))
            }
        }
    }

    // YOLOv8 の生出力(4+numClasses, boxes)を [Detection] へ変換する。
    // - 座標系: モデル出力は左上原点想定のため、Vision 用(左下原点)へY軸反転する。
    // - `.scaleFit`: letterbox (余白付き) で推論された座標を、余白を差し引いて元画像へ逆変換する。
    private func decodeYOLOv8(multiArray: MLMultiArray, imageSize: CGSize, modelInputSize: CGSize, confidenceThreshold: Double) -> YOLODecodeOutput {
        let shape = multiArray.shape.map { Int(truncating: $0) }
        guard shape.count == 3 else {
            return YOLODecodeOutput(detections: [], decodedCandidatesCount: 0, afterNMSCount: 0, sampleBBoxText: nil, sampleMappedRectText: nil)
        }

        let dim1 = shape[1]
        let dim2 = shape[2]
        let expectedChannels = 4 + classLabels.count
        let expectedObjectnessChannels = 5 + classLabels.count

        let channels: Int
        let boxCount: Int
        let channelsFirst: Bool
        // YOLOv8の出力レイアウトは [1, C, N] または [1, N, C] があり得る。
        // C(チャネル数)は「4 + class数」または objectness 付きの「5 + class数」で判定する。
        if dim1 == expectedChannels || dim1 == expectedObjectnessChannels {
            channels = dim1
            boxCount = dim2
            channelsFirst = true
        } else if dim2 == expectedChannels || dim2 == expectedObjectnessChannels {
            channels = dim2
            boxCount = dim1
            channelsFirst = false
        } else if dim1 <= dim2 {
            // 期待チャネル数が推定できないケースでは、通常 C << N であることを使い
            // 小さい次元をチャネルとして扱う（例: 1x84x2100 -> C=84, N=2100）。
            channels = dim1
            boxCount = dim2
            channelsFirst = true
        } else {
            channels = dim2
            boxCount = dim1
            channelsFirst = false
        }

        guard channels >= 5, boxCount > 0 else {
            return YOLODecodeOutput(detections: [], decodedCandidatesCount: 0, afterNMSCount: 0, sampleBBoxText: nil, sampleMappedRectText: nil)
        }
        let hasObjectness = channels == expectedObjectnessChannels
        let classStart = hasObjectness ? 5 : 4
        let classCount = max(channels - classStart, 0)
        guard classCount > 0 else {
            return YOLODecodeOutput(detections: [], decodedCandidatesCount: 0, afterNMSCount: 0, sampleBBoxText: nil, sampleMappedRectText: nil)
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

        func normalizedProbability(_ raw: Double) -> Double {
            // CoreML 変換条件によっては class/objectness が logits のまま出る場合がある。
            // 0...1 範囲外なら sigmoid を適用し、確率として扱える値へ正規化する。
            if (0.0...1.0).contains(raw) {
                return raw
            }
            return 1.0 / (1.0 + exp(-raw))
        }

        var candidates: [Detection] = []
        candidates.reserveCapacity(min(boxCount, 200))
        var sampleMappedRectText: String?

        for boxIndex in 0..<boxCount {
            let rawCenterX = valueAt(channel: 0, box: boxIndex)
            let rawCenterY = valueAt(channel: 1, box: boxIndex)
            let rawWidth = valueAt(channel: 2, box: boxIndex)
            let rawHeight = valueAt(channel: 3, box: boxIndex)

            // 一部モデルは bbox を 0...1 正規化で返すため、入力解像度へ拡大してから通常処理へ流す。
            let maxCoordinate = max(rawCenterX, rawCenterY, rawWidth, rawHeight)
            let usesNormalizedCoordinates = maxCoordinate <= 2.0
            let centerX = usesNormalizedCoordinates ? rawCenterX * modelInputSize.width : rawCenterX
            let centerY = usesNormalizedCoordinates ? rawCenterY * modelInputSize.height : rawCenterY
            let width = usesNormalizedCoordinates ? rawWidth * modelInputSize.width : rawWidth
            let height = usesNormalizedCoordinates ? rawHeight * modelInputSize.height : rawHeight

            var bestClass = 0
            var bestScore = -Double.infinity
            for classIndex in 0..<classCount {
                let score = normalizedProbability(valueAt(channel: classStart + classIndex, box: boxIndex))
                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }

            let objectness = hasObjectness ? normalizedProbability(valueAt(channel: 4, box: boxIndex)) : 1.0
            let confidence = objectness * bestScore
            guard confidence >= confidenceThreshold else { continue }

            let left = centerX - (width / 2.0)
            let top = centerY - (height / 2.0)

            // `.scaleFit` (letterbox) でモデル入力へ収めた座標を、余白込みで逆変換して元画像へ戻す。
            let mappedRect = mapScaleFitRectToImage(
                x: left,
                y: top,
                width: width,
                height: height,
                imageSize: imageSize,
                modelInputSize: modelInputSize
            )
            guard mappedRect.width > 0, mappedRect.height > 0 else { continue }

            // デバッグ用途: 1件目の候補だけ、正規化前のピクセル座標を表示して検証しやすくする。
            if sampleMappedRectText == nil {
                sampleMappedRectText = String(
                    format: "x=%.1f y=%.1f w=%.1f h=%.1f",
                    mappedRect.origin.x,
                    mappedRect.origin.y,
                    mappedRect.size.width,
                    mappedRect.size.height
                )
            }

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
            candidates.append(Detection(label: label, confidence: confidence, boundingBox: clamped))
        }

        let nms = nonMaximumSuppression(candidates, iouThreshold: yoloIouThreshold)
        let limited = Array(nms.prefix(yoloMaxDetections))
        let sampleBBoxText = limited.first.map {
            String(format: "x=%.3f y=%.3f w=%.3f h=%.3f", $0.boundingBox.origin.x, $0.boundingBox.origin.y, $0.boundingBox.size.width, $0.boundingBox.size.height)
        }
        return YOLODecodeOutput(
            detections: limited,
            decodedCandidatesCount: candidates.count,
            afterNMSCount: limited.count,
            sampleBBoxText: sampleBBoxText,
            sampleMappedRectText: sampleMappedRectText
        )
    }

    private func mapScaleFitRectToImage(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        imageSize: CGSize,
        modelInputSize: CGSize
    ) -> CGRect {
        let modelW = max(modelInputSize.width, 1)
        let modelH = max(modelInputSize.height, 1)
        let inputScale = min(modelW / imageSize.width, modelH / imageSize.height)

        // letterbox で追加されたパディング量 (モデル入力座標系)。
        let scaledImageW = imageSize.width * inputScale
        let scaledImageH = imageSize.height * inputScale
        let padX = (modelW - scaledImageW) * 0.5
        let padY = (modelH - scaledImageH) * 0.5

        // 逆変換: パディングを除去してから、元画像ピクセル座標へ戻す。
        let imageX = (x - padX) / inputScale
        let imageY = (y - padY) / inputScale
        let imageW = width / inputScale
        let imageH = height / inputScale

        // 推論ノイズで境界を少しはみ出るケースがあるため、元画像範囲へクリップする。
        let clippedMinX = max(0, min(imageSize.width, imageX))
        let clippedMinY = max(0, min(imageSize.height, imageY))
        let clippedMaxX = max(clippedMinX, min(imageSize.width, imageX + imageW))
        let clippedMaxY = max(clippedMinY, min(imageSize.height, imageY + imageH))

        return CGRect(
            x: clippedMinX,
            y: clippedMinY,
            width: clippedMaxX - clippedMinX,
            height: clippedMaxY - clippedMinY
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
