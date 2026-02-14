import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @StateObject var viewModel: ModelsViewModel
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Installed Models") {
                    ForEach(viewModel.models) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.manifest.displayName)
                                Text(model.id).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.id == viewModel.activeModelID {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("Use") { viewModel.setActive(modelID: model.id) }
                            }
                        }
                    }

                    Button("ZIPをインポート") { importing = true }
                }

                Section("Settings") {
                    Stepper("confThreshold: \(viewModel.container.modelRegistry.settings.confThreshold, specifier: "%.2f")",
                            value: $viewModel.container.modelRegistry.settings.confThreshold,
                            in: 0.1...1.0,
                            step: 0.05)
                    Stepper("stableFramesRequired: \(viewModel.container.modelRegistry.settings.stableFramesRequired)",
                            value: $viewModel.container.modelRegistry.settings.stableFramesRequired,
                            in: 1...30)
                    Stepper("minBoxAreaRatio: \(viewModel.container.modelRegistry.settings.minBoxAreaRatio, specifier: "%.3f")",
                            value: $viewModel.container.modelRegistry.settings.minBoxAreaRatio,
                            in: 0.001...0.5,
                            step: 0.005)
                    Toggle("allowMultipleDetections", isOn: $viewModel.container.modelRegistry.settings.allowMultipleDetections)
                    Button("設定を保存") { viewModel.saveSettings() }
                }

                if let importError = viewModel.importError {
                    Section("Error") { Text(importError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Models")
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType.zip]) { result in
                switch result {
                case .success(let url):
                    viewModel.importZip(url: url)
                case .failure(let error):
                    viewModel.importError = error.localizedDescription
                }
            }
        }
    }
}
