import Foundation
import AVFoundation
import UIKit

final class LogStore {
    private let root: URL
    private let logsURL: URL
    private let imagesDir: URL

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
        isStable: Bool,
        latencyMs: Double,
        fps: Double,
        detections: [Detection],
        flickerCount: Int,
        secondsToStable: Double?,
        sampleBuffer: CMSampleBuffer
    ) throws -> ScanLogEntry {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let rawURL = imagesDir.appendingPathComponent("\(stamp)-raw.jpg")
        let overlayURL = imagesDir.appendingPathComponent("\(stamp)-overlay.jpg")

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw NSError(domain: "LogStore", code: 1001)
        }

        let rawImage = Self.image(from: pixelBuffer)
        try rawImage.jpegData(compressionQuality: 0.9)?.write(to: rawURL)

        let overlayImage = Self.drawDetections(on: rawImage, detections: detections)
        try overlayImage.jpegData(compressionQuality: 0.9)?.write(to: overlayURL)

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
            rawImagePath: rawURL.path,
            overlayImagePath: overlayURL.path
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

    private static func image(from pixelBuffer: CVPixelBuffer) -> UIImage {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
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
