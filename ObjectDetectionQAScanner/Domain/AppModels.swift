import Foundation
import CoreGraphics

// MARK: - Detection primitives

struct Detection: Identifiable, Codable {
    let id: UUID
    let label: String
    let confidence: Double
    let boundingBox: CGRect

    init(id: UUID = UUID(), label: String, confidence: Double, boundingBox: CGRect) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

struct StabilitySettings: Codable {
    var confThreshold: Double = 0.55
    var stableFramesRequired: Int = 5
    var minBoxAreaRatio: Double = 0.03
    var allowMultipleDetections: Bool = false
}

enum NGReason: String, Codable, CaseIterable, Identifiable {
    case miss
    case wrongLabel = "wrong_label"
    case unstable
    case multiple
    case other

    var id: String { rawValue }
}

struct ModelMetadata: Codable, Identifiable {
    let modelID: String
    let displayName: String
    let createdAt: Date
    let classes: [String]

    var id: String { modelID }

    enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
        case displayName = "display_name"
        case createdAt = "created_at"
        case classes
    }
}

struct StoredModel: Codable, Identifiable {
    let id: String
    let metadata: ModelMetadata
    let importedAt: Date
    let compiledModelPath: String
}

struct ScanLogEntry: Codable, Identifiable {
    enum Action: String, Codable {
        case confirm
        case ng
    }

    let id: UUID
    let createdAt: Date
    let modelID: String
    let action: Action
    let ngReason: NGReason?
    let isStableAtTap: Bool
    let latencyMs: Double
    let fps: Double
    let detections: [Detection]
    let flickerCountUntilDecision: Int
    let secondsToStable: Double?
    let rawImagePath: String
    let overlayImagePath: String?
    let stabilitySettingsSnapshot: StabilitySettings

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case modelID
        case action
        case ngReason
        case isStableAtTap
        case latencyMs
        case fps
        case detections
        case flickerCountUntilDecision
        case secondsToStable
        case rawImagePath
        case overlayImagePath
        case stabilitySettingsSnapshot
    }

    init(
        id: UUID,
        createdAt: Date,
        modelID: String,
        action: Action,
        ngReason: NGReason?,
        isStableAtTap: Bool,
        latencyMs: Double,
        fps: Double,
        detections: [Detection],
        flickerCountUntilDecision: Int,
        secondsToStable: Double?,
        rawImagePath: String,
        overlayImagePath: String?,
        stabilitySettingsSnapshot: StabilitySettings
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modelID = modelID
        self.action = action
        self.ngReason = ngReason
        self.isStableAtTap = isStableAtTap
        self.latencyMs = latencyMs
        self.fps = fps
        self.detections = detections
        self.flickerCountUntilDecision = flickerCountUntilDecision
        self.secondsToStable = secondsToStable
        self.rawImagePath = rawImagePath
        self.overlayImagePath = overlayImagePath
        self.stabilitySettingsSnapshot = stabilitySettingsSnapshot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modelID = try container.decode(String.self, forKey: .modelID)
        action = try container.decode(Action.self, forKey: .action)
        ngReason = try container.decodeIfPresent(NGReason.self, forKey: .ngReason)
        isStableAtTap = try container.decode(Bool.self, forKey: .isStableAtTap)
        latencyMs = try container.decode(Double.self, forKey: .latencyMs)
        fps = try container.decode(Double.self, forKey: .fps)
        detections = try container.decode([Detection].self, forKey: .detections)
        flickerCountUntilDecision = try container.decode(Int.self, forKey: .flickerCountUntilDecision)
        secondsToStable = try container.decodeIfPresent(Double.self, forKey: .secondsToStable)
        rawImagePath = try container.decode(String.self, forKey: .rawImagePath)
        overlayImagePath = try container.decodeIfPresent(String.self, forKey: .overlayImagePath)
        // 過去ログはこのフィールドを持たないため、互換目的でデフォルト値を補う。
        stabilitySettingsSnapshot = try container.decodeIfPresent(StabilitySettings.self, forKey: .stabilitySettingsSnapshot) ?? StabilitySettings()
    }
}

struct ModelReport: Identifiable {
    let id: String
    let modelName: String
    let scanCount: Int
    let successCount: Int
    let successRate: Double
    let avgTimeToStable: Double
    let avgFlicker: Double
    let multiDetectionRate: Double
}
