import Foundation
import CoreGraphics

struct StabilityResult {
    let isStable: Bool
    let stableStreak: Int
    let flickerCount: Int
    let reason: String
    let secondsToStable: Double?
}

// 安定判定の状態機械: フレーム間の連続性と揺れ(IoU)を評価する中心ロジック。
final class StabilityEvaluator {
    private var stableStreak = 0
    private var flickerCount = 0
    private var lastLabel: String?
    private var previousBox: CGRect?
    private var sessionStart = Date()
    private var stableTimestamp: Date?

    func reset() {
        stableStreak = 0
        flickerCount = 0
        lastLabel = nil
        previousBox = nil
        sessionStart = Date()
        stableTimestamp = nil
    }

    func evaluate(detections: [Detection], settings: StabilitySettings) -> StabilityResult {
        let now = Date()
        let reason: String
        var passes = true

        if detections.isEmpty {
            passes = false
            reason = "no_detection"
            flickerCount += 1
            stableStreak = 0
            return result(isStable: false, reason: reason)
        }

        if !settings.allowMultipleDetections && detections.count != 1 {
            passes = false
            reason = "multiple_detection"
            stableStreak = 0
            return result(isStable: false, reason: reason)
        }

        guard let primary = detections.max(by: { $0.confidence < $1.confidence }) else {
            return result(isStable: false, reason: "unknown")
        }

        let boxArea = primary.boundingBox.width * primary.boundingBox.height
        if primary.confidence < settings.confThreshold {
            passes = false
            reason = "low_confidence"
        } else if boxArea < settings.minBoxAreaRatio {
            passes = false
            reason = "small_box"
        } else if let previousBox {
            let iouScore = Self.iou(previous: previousBox, current: primary.boundingBox)
            if iouScore < 0.7 {
                passes = false
                reason = "bbox_jitter"
            } else {
                reason = "ok"
            }
        } else {
            reason = "ok"
        }

        if let lastLabel, lastLabel != primary.label {
            flickerCount += 1
        }
        self.lastLabel = primary.label
        previousBox = primary.boundingBox

        if passes {
            stableStreak += 1
            if stableStreak >= settings.stableFramesRequired, stableTimestamp == nil {
                stableTimestamp = now
            }
        } else {
            stableStreak = 0
        }

        return result(isStable: stableStreak >= settings.stableFramesRequired, reason: reason)
    }

    private func result(isStable: Bool, reason: String) -> StabilityResult {
        let seconds = stableTimestamp.map { $0.timeIntervalSince(sessionStart) }
        return StabilityResult(
            isStable: isStable,
            stableStreak: stableStreak,
            flickerCount: flickerCount,
            reason: reason,
            secondsToStable: seconds
        )
    }

    static func iou(previous: CGRect, current: CGRect) -> Double {
        let intersection = previous.intersection(current)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (previous.width * previous.height) + (current.width * current.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}
