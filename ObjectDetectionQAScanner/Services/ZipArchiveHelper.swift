import Foundation

struct ZipArchiveHelper {
    static func unzip(source: URL, destination: URL) throws {
        guard let archive = Archive(url: source, accessMode: .read) else {
            throw NSError(domain: "zip", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot open ZIP"])
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        for entry in archive {
            let outputURL = destination.appendingPathComponent(entry.path)
            _ = try archive.extract(entry, to: outputURL)
        }
    }

    static func zip(directory: URL, outputZipURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputZipURL.path) {
            try fm.removeItem(at: outputZipURL)
        }
        guard let archive = Archive(url: outputZipURL, accessMode: .create) else {
            throw NSError(domain: "zip", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot create ZIP"])
        }

        let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: directory.path + "/", with: "")
            try archive.addEntry(with: relativePath, relativeTo: directory)
        }
    }
}
