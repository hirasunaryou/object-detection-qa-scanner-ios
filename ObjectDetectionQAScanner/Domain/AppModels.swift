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
