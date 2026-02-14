import CoreGraphics
import Foundation

/// stable状態をフレーム連続条件で評価する小さな状態機械。
final class StabilityEvaluator {
    private(set) var stableFrameCount = 0
    private(set) var flickerCount = 0
    private var previousLabel: String?
    private var previousBox: CGRect?
    private var startDate: Date?

    func reset() {
        stableFrameCount = 0
        flickerCount = 0
        previousLabel = nil
        previousBox = nil
        startDate = nil
    }

    /// 毎フレーム呼び出し、stable判定とflickerを更新する。
    func evaluate(detections: [DetectionResult], settings: ScanSettings) -> FrameStabilityState {
        if startDate == nil { startDate = Date() }

        let isCandidate = passesConditions(detections: detections, settings: settings)
        if isCandidate {
            stableFrameCount += 1
        } else {
            trackFlicker(detections: detections)
            stableFrameCount = 0
        }

        if let first = detections.first {
            previousLabel = first.label
            previousBox = first.boundingBox
        } else {
            previousLabel = nil
            previousBox = nil
        }

        return FrameStabilityState(
            isStable: stableFrameCount >= settings.stableFramesRequired,
            stableFrameCount: stableFrameCount,
            flickerCount: flickerCount
        )
    }

    func elapsedToStableMS() -> Double? {
        guard let startDate else { return nil }
        return Date().timeIntervalSince(startDate) * 1000
    }

    private func passesConditions(detections: [DetectionResult], settings: ScanSettings) -> Bool {
        if settings.allowMultipleDetections {
            guard let first = detections.first else { return false }
            return first.confidence >= settings.confThreshold && areaRatio(of: first.boundingBox) >= settings.minBoxAreaRatio
        }

        guard detections.count == 1, let detection = detections.first else {
            return false
        }

        guard detection.confidence >= settings.confThreshold,
              areaRatio(of: detection.boundingBox) >= settings.minBoxAreaRatio else {
            return false
        }

        if let prev = previousBox {
            return Self.iou(lhs: prev, rhs: detection.boundingBox) >= 0.7
        }

        return true
    }

    private func trackFlicker(detections: [DetectionResult]) {
        if detections.isEmpty {
            flickerCount += 1
            return
        }
        if let prevLabel = previousLabel, prevLabel != detections.first?.label {
            flickerCount += 1
        }
    }

    private func areaRatio(of rect: CGRect) -> Double {
        Double(rect.width * rect.height)
    }

    static func iou(lhs: CGRect, rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return Double(intersectionArea / unionArea)
    }
}
