import Foundation

struct Exporter {
    func createExportZip(from rootDirectory: URL) throws -> URL {
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_export_\(Int(Date().timeIntervalSince1970)).zip")
        try ZipArchiveHelper.zip(directory: rootDirectory, outputZipURL: zipURL)
        return zipURL
    }
}
