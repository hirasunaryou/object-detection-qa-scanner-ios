import Foundation
import Combine

final class SettingsStore: ObservableObject {
    @Published var settings: StabilitySettings {
        didSet { persist() }
    }

    private let url: URL

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(StabilitySettings.self, from: data) {
            settings = decoded
        } else {
            settings = StabilitySettings()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
