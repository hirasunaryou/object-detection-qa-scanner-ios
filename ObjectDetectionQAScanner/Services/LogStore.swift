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
    private let debugLogStore: DebugLogStore
    private let maxStorageBytes: Int64 = 500 * 1024 * 1024
    private let targetStorageBytesAfterRotation: Int64 = 400 * 1024 * 1024

    init(debugLogStore: DebugLogStore = .shared) {
        self.debugLogStore = debugLogStore
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
        sampleBuffer: CMSampleBuffer,
        exifOrientation: CGImagePropertyOrientation
    ) throws -> ScanLogEntry {
        let imageCountBeforeSave = (try? imageFileRecordsSortedByCreationDate(ascending: true).count) ?? 0
        debugLogStore.info(tag: "LogStore", message: "save_scan_start", fields: ["model_id": modelID, "action": action.rawValue, "detections_count": detections.count, "image_files_before": imageCountBeforeSave])

        // タイムスタンプ + UUID でファイル名衝突を防ぐ。
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let uniqueID = UUID().uuidString
        let rawRelativePath = "images/\(stamp)-\(uniqueID)-raw.jpg"
        let overlayRelativePath = "images/\(stamp)-\(uniqueID)-overlay.jpg"
        let rawURL = root.appendingPathComponent(rawRelativePath)
        let overlayURL = root.appendingPathComponent(overlayRelativePath)

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            debugLogStore.error(tag: "LogStore", message: "save_scan_error", fields: ["reason": "failed_to_extract_pixel_buffer", "model_id": modelID])
            throw LogStoreError.failedToExtractPixelBuffer
        }

        // 推論時と同じ EXIF 向きで正規化して保存し、Live オーバーレイとの座標整合を保つ。
        let rawImage = Self.image(from: pixelBuffer, orientation: exifOrientation)
        guard let rawJPEG = rawImage.jpegData(compressionQuality: 0.9) else {
            debugLogStore.error(tag: "LogStore", message: "save_scan_error", fields: ["reason": "failed_to_encode_raw_jpeg", "model_id": modelID])
            throw LogStoreError.failedToEncodeJPEG(kind: "raw")
        }
        try rawJPEG.write(to: rawURL, options: .atomic)

        let overlayImage = Self.drawDetections(on: rawImage, detections: detections)
        guard let overlayJPEG = overlayImage.jpegData(compressionQuality: 0.9) else {
            debugLogStore.error(tag: "LogStore", message: "save_scan_error", fields: ["reason": "failed_to_encode_overlay_jpeg", "model_id": modelID])
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

        try autoRotateIfNeeded()

        let imageCountAfterSave = (try? imageFileRecordsSortedByCreationDate(ascending: true).count) ?? 0
        debugLogStore.info(
            tag: "LogStore",
            message: "save_scan_end",
            fields: [
                "model_id": modelID,
                "raw_image_path": rawRelativePath,
                "overlay_image_path": overlayRelativePath,
                "detections_count": detections.count,
                "image_files_after": imageCountAfterSave
            ]
        )

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

    func computeQADataSizeBytes() -> Int64 {
        (try? directorySize(at: root)) ?? 0
    }

    func computeQADataSizeText() -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: computeQADataSizeBytes())
    }

    @discardableResult
    func deleteImagesOnly() throws -> Int {
        let imageFiles = try imageFileRecordsSortedByCreationDate(ascending: true)
        var removedCount = 0
        for file in imageFiles {
            try FileManager.default.removeItem(at: file.url)
            removedCount += 1
        }
        debugLogStore.info(tag: "LogStore", message: "delete_images_only", fields: ["removed_files": removedCount])
        return removedCount
    }

    func deleteAllQAData() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        debugLogStore.info(tag: "LogStore", message: "delete_all_qadata", fields: ["root_path": root.path])
    }

    private func autoRotateIfNeeded() throws {
        let initialSize = computeQADataSizeBytes()
        guard initialSize > maxStorageBytes else { return }

        var currentSize = initialSize
        var removedFiles = 0
        let candidates = try imageFileRecordsSortedByCreationDate(ascending: true)

        debugLogStore.warn(tag: "LogStore", message: "auto_rotation_start", fields: ["current_size_bytes": initialSize, "max_size_bytes": maxStorageBytes, "target_size_bytes": targetStorageBytesAfterRotation, "image_files": candidates.count])

        for record in candidates {
            try FileManager.default.removeItem(at: record.url)
            removedFiles += 1
            currentSize -= record.size
            if currentSize <= targetStorageBytesAfterRotation {
                break
            }
        }

        debugLogStore.info(tag: "LogStore", message: "auto_rotation_end", fields: ["removed_files": removedFiles, "final_size_bytes": max(currentSize, 0)])
    }

    private func imageFileRecordsSortedByCreationDate(ascending: Bool) throws -> [(url: URL, createdAt: Date, size: Int64)] {
        guard FileManager.default.fileExists(atPath: imagesDir.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles])

        let records = urls.compactMap { url -> (url: URL, createdAt: Date, size: Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return nil
            }
            let timestamp = values.creationDate ?? values.contentModificationDate ?? .distantPast
            let size = Int64(values.fileSize ?? 0)
            return (url: url, createdAt: timestamp, size: size)
        }

        return records.sorted { ascending ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt }
    }

    private func directorySize(at rootURL: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: rootURL.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
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
