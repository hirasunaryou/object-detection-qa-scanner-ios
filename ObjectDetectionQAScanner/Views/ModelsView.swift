import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @EnvironmentObject private var modelStore: ModelStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var modelsViewModel: ModelsViewModel
    @ObservedObject var liveViewModel: LiveViewModel

    @State private var showingImporter = false

    var body: some View {
        NavigationStack {
            Form {
                importedModelsSection

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
                isPresented: $showingImporter,
                allowedContentTypes: [.zip],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert("Import Failed", isPresented: importErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(modelsViewModel.importError ?? "Unknown error")
            }
        }
    }

    // MARK: - Sections

    /// モデル一覧・選択・インポート導線をひとかたまりとして分離し、
    /// 設定フォームとの責務分離を明確にする。
    private var importedModelsSection: some View {
        Section("Imported models") {
            if modelStore.models.isEmpty {
                Text("モデル未登録です。ZIP をインポートして開始してください。")
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
                        activateModel(model)
                    }
                }
            }

            Button("Import ZIP") {
                showingImporter = true
            }
        }
    }

    // MARK: - Actions

    private func activateModel(_ model: StoredModel) {
        modelStore.setActive(modelID: model.id)
        try? liveViewModel.applyModel(model, from: modelStore)
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            modelsViewModel.importZip(url: url)

            // インポート成功時は activeModelID が更新されるので、
            // そのIDを見て Live 側にも同じモデルを反映する。
            if let imported = modelStore.models.first(where: { $0.id == modelStore.activeModelID }) {
                try? liveViewModel.applyModel(imported, from: modelStore)
            }
        case .failure(let error):
            modelsViewModel.importError = error.localizedDescription
        }
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { modelsViewModel.importError != nil },
            set: { isPresented in
                if !isPresented {
                    modelsViewModel.importError = nil
                }
            }
        )
    }
}
