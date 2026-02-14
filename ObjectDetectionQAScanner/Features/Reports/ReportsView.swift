import SwiftUI

struct ReportsView: View {
    @StateObject var viewModel: ReportsViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.metrics) { metric in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(metric.modelName).font(.headline)
                        Text("scan_count: \(metric.scanCount)")
                        Text("success_count: \(metric.successCount)")
                        Text("success_rate: \(metric.successRate * 100, specifier: "%.1f")%")
                        Text("avg_time_to_stable: \(metric.avgTimeToStable, specifier: "%.1f") ms")
                        Text("avg_flicker: \(metric.avgFlicker, specifier: "%.2f")")
                        Text("multi_detection_rate: \(metric.multiDetectionRate * 100, specifier: "%.1f")%")
                    }
                }
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Reload") { viewModel.reload() }
                    Button("Export ZIP") { viewModel.export() }
                }
            }
            .sheet(isPresented: Binding(get: { viewModel.exportURL != nil }, set: { if !$0 { viewModel.exportURL = nil } })) {
                if let url = viewModel.exportURL {
                    ActivityView(items: [url])
                }
            }
            .alert("Export Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
