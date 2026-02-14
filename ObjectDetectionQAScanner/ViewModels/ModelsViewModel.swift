import Foundation
import Combine

@MainActor
final class ModelsViewModel: ObservableObject {
    @Published var importError: String?

    let modelStore: ModelStore
    let settingsStore: SettingsStore

    init(modelStore: ModelStore, settingsStore: SettingsStore) {
        self.modelStore = modelStore
        self.settingsStore = settingsStore
    }

    func importZip(url: URL) {
        do {
            try modelStore.importModelZip(from: url)
        } catch {
            importError = error.localizedDescription
        }
    }
}
