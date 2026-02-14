import SwiftUI

@main
struct ObjectDetectionQAScannerApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(container)
        }
    }
}
