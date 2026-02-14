import Foundation

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published var metrics: [ModelMetrics] = []
    @Published var exportURL: URL?
    @Published var errorMessage: String?

    private let container: AppContainer
    private let exporter = Exporter()

    init(container: AppContainer) {
        self.container = container
        reload()
    }

    func reload() {
        let logs = container.logStore.loadLogs()
        let grouped = Dictionary(grouping: logs, by: { $0.modelID })
        metrics = grouped.map { modelID, entries in
            let success = entries.filter { $0.status == "success" }
            let multiCount = entries.filter { $0.detectionCount > 1 }.count
            return ModelMetrics(
                id: modelID,
                modelName: entries.first?.modelName ?? modelID,
                scanCount: entries.count,
                successCount: success.count,
                successRate: ratio(success.count, entries.count),
                avgTimeToStable: average(success.compactMap(\.timeToStableMS)),
                avgFlicker: average(entries.map { Double($0.flickerCount) }),
                multiDetectionRate: ratio(multiCount, entries.count)
            )
        }
        .sorted(by: { $0.scanCount > $1.scanCount })
    }

    func export() {
        do {
            exportURL = try exporter.createExportZip(from: container.logStore.exportDirectory())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func ratio(_ num: Int, _ den: Int) -> Double {
        guard den > 0 else { return 0 }
        return Double(num) / Double(den)
    }
}
