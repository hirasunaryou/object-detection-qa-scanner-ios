import Foundation
import AVFoundation
import UIKit
import ImageIO

final class LogStore {
    enum LogStoreError: LocalizedError {
        case failedToExtractPixelBuffer
        case failedToEncodeJPEG(kind: String)

        var errorDescription: String? {
            switch self {
            case .failedToExtractPixelBuffer:
                return "保存対象の画像バッファを取得できませんでした。"
            case .failedToEncodeJPEG(let kind):
                return "\(kind) 画像の JPEG エンコードに失敗しました。"
            }
        }
    }

    private let root: URL
    private let logsURL: URL
    private let imagesDir: URL
    // Vision推論と保存画像で向きを統一するため、ここでも .right を明示する。
    private let inferenceOrientation: CGImagePropertyOrientation = .right

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = support.appendingPathComponent("QAData", isDirectory: true)
        logsURL = root.appendingPathComponent("scan_logs.jsonl")
        imagesDir = root.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    var rootDirectory: URL { root }

    @discardableResult
    func saveScan(
        modelID: String,
        action: ScanLogEntry.Action,
        ngReason: NGReason?,
        stabilitySettings: StabilitySettings,
        isStable: Bool,
        latencyMs: Double,
        fps: Double,
        detections: [Detection],
        flickerCount: Int,
        secondsToStable: Double?,
        sampleBuffer: CMSampleBuffer
    ) throws -> ScanLogEntry {
        // タイムスタンプ + UUID でファイル名衝突を防ぐ。
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let uniqueID = UUID().uuidString
        let rawRelativePath = "images/\(stamp)-\(uniqueID)-raw.jpg"
        let overlayRelativePath = "images/\(stamp)-\(uniqueID)-overlay.jpg"
        let rawURL = root.appendingPathComponent(rawRelativePath)
        let overlayURL = root.appendingPathComponent(overlayRelativePath)

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw LogStoreError.failedToExtractPixelBuffer
        }

        // Vision(.right) と同じ向きに正規化した画像を保存する。
        let rawImage = Self.image(from: pixelBuffer, orientation: inferenceOrientation)
        guard let rawJPEG = rawImage.jpegData(compressionQuality: 0.9) else {
            throw LogStoreError.failedToEncodeJPEG(kind: "raw")
        }
        try rawJPEG.write(to: rawURL, options: .atomic)

        let overlayImage = Self.drawDetections(on: rawImage, detections: detections)
        guard let overlayJPEG = overlayImage.jpegData(compressionQuality: 0.9) else {
            throw LogStoreError.failedToEncodeJPEG(kind: "overlay")
        }
        try overlayJPEG.write(to: overlayURL, options: .atomic)

        let entry = ScanLogEntry(
            id: UUID(),
            createdAt: Date(),
            modelID: modelID,
            action: action,
            ngReason: ngReason,
            isStableAtTap: isStable,
            latencyMs: latencyMs,
            fps: fps,
            detections: detections,
            flickerCountUntilDecision: flickerCount,
            secondsToStable: secondsToStable,
            rawImagePath: rawRelativePath,
            overlayImagePath: overlayRelativePath,
            stabilitySettingsSnapshot: stabilitySettings
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = try encoder.encode(entry)
        if !FileManager.default.fileExists(atPath: logsURL.path) {
            FileManager.default.createFile(atPath: logsURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logsURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        handle.write(line)
        handle.write("\n".data(using: .utf8)!)

        return entry
    }

    func loadEntries() -> [ScanLogEntry] {
        guard let data = try? Data(contentsOf: logsURL), let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text
            .split(separator: "\n")
            .compactMap { try? decoder.decode(ScanLogEntry.self, from: Data($0.utf8)) }
    }

    private static func image(from pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> UIImage {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(forExifOrientation: Int32(orientation.rawValue))
        let context = CIContext(options: nil)
        let rect = ci.extent
        let cg = context.createCGImage(ci, from: rect)!
        return UIImage(cgImage: cg)
    }

    private static func drawDetections(on image: UIImage, detections: [Detection]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            ctx.cgContext.setLineWidth(3)
            for detection in detections {
                let rect = CGRect(
                    x: detection.boundingBox.origin.x * image.size.width,
                    y: (1 - detection.boundingBox.origin.y - detection.boundingBox.height) * image.size.height,
                    width: detection.boundingBox.width * image.size.width,
                    height: detection.boundingBox.height * image.size.height
                )
                UIColor.systemGreen.setStroke()
                ctx.cgContext.stroke(rect)
                let text = "\(detection.label) \(String(format: "%.2f", detection.confidence))"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .backgroundColor: UIColor.black.withAlphaComponent(0.6)
                ]
                text.draw(at: CGPoint(x: rect.minX + 2, y: max(2, rect.minY - 18)), withAttributes: attrs)
            }
        }
    }
}
