import Foundation

final class Exporter {
    // iOS 16 互換のため ZIP ではなく共有用ディレクトリを返す暫定実装。
    func makeExportDirectory(from root: URL) throws -> URL {
        // ShareSheetに渡すために、アプリの永続領域を直接公開せず一時領域へコピーを作成する。
        // こうすることで、共有中に元データ構造を壊すリスクを減らせる。
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("qa-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        let copyRoot = temp.appendingPathComponent("QAExport", isDirectory: true)
        if FileManager.default.fileExists(atPath: copyRoot.path) {
            try FileManager.default.removeItem(at: copyRoot)
        }
        try FileManager.default.copyItem(at: root, to: copyRoot)
        return copyRoot
    }
}
