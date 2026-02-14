import SwiftUI
import UIKit

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ReportsView: View {
    @ObservedObject var viewModel: ReportsViewModel
    let exporter: Exporter
    let rootURL: URL

    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            VStack {
                List(viewModel.reports) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.modelName).font(.headline)
                        Text("scan_count: \(report.scanCount)")
                        Text("success_count: \(report.successCount)")
                        Text("success_rate: \(report.successRate * 100, specifier: "%.1f")%")
                        Text("avg_time_to_stable: \(report.avgTimeToStable, specifier: "%.2f")s")
                        Text("avg_flicker: \(report.avgFlicker, specifier: "%.2f")")
                        Text("multi_detection_rate: \(report.multiDetectionRate * 100, specifier: "%.1f")%")
                    }
                }

                HStack {
                    Button("Refresh") { viewModel.refresh() }
                    Button("ログと画像フォルダを共有") {
                        do {
                            shareItem = ShareItem(url: try exporter.makeExportDirectory(from: rootURL))
                        } catch {
                            shareItem = nil
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            .navigationTitle("Reports")
            .sheet(item: $shareItem) { item in
                ActivityView(activityItems: [item.url])
            }
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
