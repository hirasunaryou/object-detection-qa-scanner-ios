import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @EnvironmentObject private var modelStore: ModelStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject var viewModel: ModelsViewModel
    @ObservedObject var liveViewModel: LiveViewModel
    @State private var isImporterPresented = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Imported models") {
                    if modelStore.models.isEmpty {
                        Text("モデル未登録です。ZIPをimportして利用を開始してください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(modelStore.models) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.metadata.displayName)
                                Text(model.metadata.modelID).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if modelStore.activeModelID == model.id {
                                Text("Active").foregroundStyle(.green)
                            }
                            Button("Use") {
                                modelStore.setActive(modelID: model.id)
                                try? liveViewModel.applyModel(model, from: modelStore)
                            }
                        }
                    }

                    Button("Import ZIP") {
                        isImporterPresented = true
                    }
                }

                Section("Stability settings") {
                    Slider(value: $settingsStore.settings.confThreshold, in: 0.1...0.99) {
                        Text("confThreshold")
                    } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("0.99") }
                    Text("confThreshold: \(settingsStore.settings.confThreshold, specifier: "%.2f")")

                    Stepper("stableFramesRequired: \(settingsStore.settings.stableFramesRequired)", value: $settingsStore.settings.stableFramesRequired, in: 1...30)

                    Slider(value: $settingsStore.settings.minBoxAreaRatio, in: 0.001...0.5) {
                        Text("minBoxAreaRatio")
                    }
                    Text("minBoxAreaRatio: \(settingsStore.settings.minBoxAreaRatio, specifier: "%.3f")")

                    Toggle("allowMultipleDetections", isOn: $settingsStore.settings.allowMultipleDetections)
                }
            }
            .navigationTitle("Models")
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let selectedURL = urls.first else { return }
                    let didStart = selectedURL.startAccessingSecurityScopedResource()
                    defer {
                        if didStart {
                            selectedURL.stopAccessingSecurityScopedResource()
                        }
                    }
                    viewModel.importZip(url: selectedURL)
                    if let activeID = modelStore.activeModelID,
                       let activeModel = modelStore.models.first(where: { $0.id == activeID }) {
                        try? liveViewModel.applyModel(activeModel, from: modelStore)
                    }
                case .failure(let error):
                    viewModel.importError = error.localizedDescription
                }
            }
            .alert("Import failed", isPresented: Binding(
                get: { viewModel.importError != nil },
                set: { newValue in
                    if !newValue {
                        viewModel.importError = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.importError = nil
                }
            } message: {
                Text(viewModel.importError ?? "Unknown error")
            }
        }
    }
}
