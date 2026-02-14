import CoreGraphics
import Foundation

enum NGReason: String, Codable, CaseIterable, Identifiable {
    case miss
    case wrongLabel = "wrong_label"
    case unstable
    case multiple
    case other

    var id: String { rawValue }
}

struct DetectionResult: Identifiable, Codable {
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

struct ScanSettings: Codable {
    var confThreshold: Double = 0.6
    var stableFramesRequired: Int = 8
    var minBoxAreaRatio: Double = 0.03
    var allowMultipleDetections: Bool = false

    static let `default` = ScanSettings()
}

struct ModelManifest: Codable, Identifiable {
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

struct InstalledModel: Codable, Identifiable {
    let id: String
    let manifest: ModelManifest
    let compiledModelPath: String
    let importedAt: Date
}

struct FrameStabilityState {
    var isStable: Bool
    var stableFrameCount: Int
    var flickerCount: Int
}

struct ScanLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let modelID: String
    let modelName: String
    let status: String
    let reason: String?
    let latencyMS: Double
    let fps: Double
    let timeToStableMS: Double?
    let flickerCount: Int
    let detectionCount: Int
    let labels: [String]
    let imageFilename: String
}

struct ModelMetrics: Identifiable {
    let id: String
    let modelName: String
    let scanCount: Int
    let successCount: Int
    let successRate: Double
    let avgTimeToStable: Double
    let avgFlicker: Double
    let multiDetectionRate: Double
}
