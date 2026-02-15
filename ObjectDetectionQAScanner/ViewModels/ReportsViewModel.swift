import Foundation
import Combine

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var reports: [ModelReport] = []
    @Published var qaDataSizeText: String = "0 KB"

    private let logStore: LogStore

    init(logStore: LogStore) {
        self.logStore = logStore
        refresh()
    }

    func refresh() {
        let entries = logStore.loadEntries()
        let grouped = Dictionary(grouping: entries, by: { $0.modelID })

        reports = grouped.map { modelID, logs in
            let scanCount = logs.count
            let successCount = logs.filter { $0.action == .confirm }.count
            let successRate = scanCount > 0 ? Double(successCount) / Double(scanCount) : 0
            let stableTimes = logs.compactMap(\.secondsToStable)
            let flickers = logs.map { Double($0.flickerCountUntilDecision) }
            let multiCount = logs.filter { $0.detections.count > 1 }.count

            return ModelReport(
                id: modelID,
                modelName: modelID,
                scanCount: scanCount,
                successCount: successCount,
                successRate: successRate,
                avgTimeToStable: stableTimes.isEmpty ? 0 : stableTimes.reduce(0, +) / Double(stableTimes.count),
                avgFlicker: flickers.isEmpty ? 0 : flickers.reduce(0, +) / Double(flickers.count),
                multiDetectionRate: scanCount > 0 ? Double(multiCount) / Double(scanCount) : 0
            )
        }
        .sorted { $0.modelName < $1.modelName }

        qaDataSizeText = logStore.computeQADataSizeText()
    }

    func deleteImagesOnly() -> Bool {
        do {
            _ = try logStore.deleteImagesOnly()
            refresh()
            return true
        } catch {
            return false
        }
    }

    func deleteAllQAData() -> Bool {
        do {
            try logStore.deleteAllQAData()
            refresh()
            return true
        } catch {
            return false
        }
    }
}
