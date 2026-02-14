import SwiftUI

struct ModelsView: View {
    @EnvironmentObject private var modelStore: ModelStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @ObservedObject var liveViewModel: LiveViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Imported models") {
                    if modelStore.models.isEmpty {
                        Text("モデル未登録です。ZIP import は iOS 16 対応のため一時停止中です。")
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

                    Button("ZIPをimport（一時停止）") {}
                        .disabled(true)
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
        }
    }
}
