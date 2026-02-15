import Foundation

final class Exporter {
    private let debugLogStore: DebugLogStore

    init(debugLogStore: DebugLogStore = .shared) {
        self.debugLogStore = debugLogStore
    }

    // iOS 16 互換のため ZIP ではなく共有用ディレクトリを返す暫定実装。
    func makeExportDirectory(from root: URL) throws -> URL {
        let sourceFileCount = fileCount(under: root)
        debugLogStore.info(tag: "Exporter", message: "export_start", fields: ["root_path": root.path, "source_file_count": sourceFileCount])

        // ShareSheetに渡すために、アプリの永続領域を直接公開せず一時領域へコピーを作成する。
        // こうすることで、共有中に元データ構造を壊すリスクを減らせる。
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("qa-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let copyRoot = temp.appendingPathComponent("QAExport", isDirectory: true)
        if FileManager.default.fileExists(atPath: copyRoot.path) {
            try FileManager.default.removeItem(at: copyRoot)
        }
        do {
            try FileManager.default.copyItem(at: root, to: copyRoot)
            let count = fileCount(under: copyRoot)
            debugLogStore.info(tag: "Exporter", message: "export_end", fields: ["export_path": copyRoot.path, "file_count": count])
            return copyRoot
        } catch {
            debugLogStore.error(tag: "Exporter", message: "export_error", fields: ["root_path": root.path, "error": error.localizedDescription])
            throw error
        }
    }

    private func fileCount(under url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var count = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                count += 1
            }
        }
        return count
    }
}
