import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @ObservedObject var viewModel: ModelsViewModel
    @ObservedObject var liveViewModel: LiveViewModel

    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Imported models") {
                    ForEach(viewModel.modelStore.models) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.metadata.displayName)
                                Text(model.metadata.modelID).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.modelStore.activeModelID == model.id {
                                Text("Active").foregroundStyle(.green)
                            }
                            Button("Use") {
                                viewModel.modelStore.setActive(modelID: model.id)
                                try? liveViewModel.applyModel(model, from: viewModel.modelStore)
                            }
                        }
                    }

                    Button("ZIPをimport") { importing = true }
                }

                Section("Stability settings") {
                    Slider(value: $viewModel.settingsStore.settings.confThreshold, in: 0.1...0.99) {
                        Text("confThreshold")
                    } minimumValueLabel: { Text("0.1") } maximumValueLabel: { Text("0.99") }
                    Text("confThreshold: \(viewModel.settingsStore.settings.confThreshold, specifier: "%.2f")")

                    Stepper("stableFramesRequired: \(viewModel.settingsStore.settings.stableFramesRequired)", value: $viewModel.settingsStore.settings.stableFramesRequired, in: 1...30)

                    Slider(value: $viewModel.settingsStore.settings.minBoxAreaRatio, in: 0.001...0.5) {
                        Text("minBoxAreaRatio")
                    }
                    Text("minBoxAreaRatio: \(viewModel.settingsStore.settings.minBoxAreaRatio, specifier: "%.3f")")

                    Toggle("allowMultipleDetections", isOn: $viewModel.settingsStore.settings.allowMultipleDetections)
                }
            }
            .navigationTitle("Models")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                viewModel.importZip(url: url)
            }
            .alert("Import Error", isPresented: Binding(get: { viewModel.importError != nil }, set: { _ in viewModel.importError = nil })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.importError ?? "Unknown")
            }
        }
    }
}
