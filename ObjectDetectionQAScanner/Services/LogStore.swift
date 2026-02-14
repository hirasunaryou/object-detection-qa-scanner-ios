import Foundation
import UIKit

final class LogStore: ObservableObject {
    private let fm = FileManager.default

    private var rootURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("scan_logs", isDirectory: true)
    }

    private var logURL: URL { rootURL.appendingPathComponent("events.jsonl") }
    private var imageDirectory: URL { rootURL.appendingPathComponent("images", isDirectory: true) }

    init() {
        try? fm.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
    }

    func append(_ entry: ScanLogEntry) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry),
              var string = String(data: data, encoding: .utf8) else { return }
        string += "\n"

        if fm.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(string.utf8))
        } else {
            try? Data(string.utf8).write(to: logURL)
        }
    }

    func saveImage(_ image: UIImage, prefix: String) -> String {
        let filename = "\(prefix)_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let url = imageDirectory.appendingPathComponent(filename)
        if let data = image.jpegData(compressionQuality: 0.92) {
            try? data.write(to: url)
        }
        return filename
    }

    func loadLogs() -> [ScanLogEntry] {
        guard let raw = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return raw.split(separator: "\n").compactMap { line in
            try? decoder.decode(ScanLogEntry.self, from: Data(line.utf8))
        }
    }

    func exportDirectory() -> URL {
        rootURL
    }
}
