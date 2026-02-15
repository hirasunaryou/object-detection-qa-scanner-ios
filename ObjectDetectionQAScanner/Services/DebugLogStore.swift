import Foundation

// QAData/debug.log へ JSON Lines 形式で非同期追記する軽量ロガー。
// UI スレッドを塞がないため、専用シリアルキューでファイルI/Oを直列化する。
final class DebugLogStore {
    enum Level: String {
        case info
        case warn
        case error
    }

    static let shared = DebugLogStore()

    private let queue = DispatchQueue(label: "debug-log-store.queue", qos: .utility)
    private let fileURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = support.appendingPathComponent("QAData", isDirectory: true)
        fileURL = root.appendingPathComponent("debug.log")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func info(tag: String, message: String, fields: [String: Any] = [:]) {
        log(level: .info, tag: tag, message: message, fields: fields)
    }

    func warn(tag: String, message: String, fields: [String: Any] = [:]) {
        log(level: .warn, tag: tag, message: message, fields: fields)
    }

    func error(tag: String, message: String, fields: [String: Any] = [:]) {
        log(level: .error, tag: tag, message: message, fields: fields)
    }

    // 要件の helper。デフォルトは info として扱う。
    func log(tag: String, message: String, fields: [String: Any] = [:]) {
        log(level: .info, tag: tag, message: message, fields: fields)
    }

    private func log(level: Level, tag: String, message: String, fields: [String: Any]) {
        queue.async {
            let payload: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "level": level.rawValue,
                "tag": tag,
                "message": message,
                // Privacy: デバッグログには生バイトを入れず、JSONで表現可能な値だけ保存する。
                "fields": Self.sanitize(fields)
            ]

            guard JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let lineBreak = "\n".data(using: .utf8)
            else {
                return
            }

            if !FileManager.default.fileExists(atPath: self.fileURL.path) {
                FileManager.default.createFile(atPath: self.fileURL.path, contents: nil)
            }

            do {
                let handle = try FileHandle(forWritingTo: self.fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                handle.write(data)
                handle.write(lineBreak)
            } catch {
                // デバッグログ書き込み失敗で本処理を止めない。
            }
        }
    }

    private static func sanitize(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let double as Double:
            return double
        case let float as Float:
            return Double(float)
        case let number as NSNumber:
            return number
        case let date as Date:
            return ISO8601DateFormatter().string(from: date)
        case let url as URL:
            return url.path
        case let array as [Any]:
            return array.map { sanitize($0) }
        case let dict as [String: Any]:
            return sanitize(dict)
        default:
            return String(describing: value)
        }
    }

    private static func sanitize(_ dictionary: [String: Any]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: dictionary.map { key, value in
            (key, sanitize(value))
        })
    }
}
