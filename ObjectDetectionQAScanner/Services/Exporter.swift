import Foundation

final class Exporter {
    func makeExportZip(from root: URL) throws -> URL {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("qa-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let copyRoot = temp.appendingPathComponent("QAExport", isDirectory: true)
        try FileManager.default.copyItem(at: root, to: copyRoot)

        let zipURL = temp.appendingPathComponent("qa-export.zip")
        try FileManager.default.zipItem(at: copyRoot, to: zipURL)
        return zipURL
    }
}
