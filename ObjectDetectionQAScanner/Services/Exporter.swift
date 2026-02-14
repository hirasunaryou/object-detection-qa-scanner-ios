import Foundation

final class Exporter {
    // iOS 16 互換のため ZIP ではなく共有用ディレクトリを返す暫定実装。
    func makeExportDirectory(from root: URL) throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("qa-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let copyRoot = temp.appendingPathComponent("QAExport", isDirectory: true)
        try FileManager.default.copyItem(at: root, to: copyRoot)
        return copyRoot
    }
}
