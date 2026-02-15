import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        TabView {
            LiveView(viewModel: container.liveViewModel)
                .tabItem { Label("Live", systemImage: "camera.viewfinder") }

            ModelsView(liveViewModel: container.liveViewModel)
                .tabItem { Label("Models", systemImage: "shippingbox") }

            ReportsView(viewModel: container.reportsViewModel, exporter: container.exporter, rootURL: container.logStore.rootDirectory)
                .tabItem { Label("Reports", systemImage: "chart.xyaxis.line") }
        }
        .onAppear {
            container.activateCurrentModelIfPossible()
        }
    }
}

#Preview {
    let container = AppContainer()
    return ContentView()
        .environmentObject(container)
        .environmentObject(container.modelStore)
        .environmentObject(container.settingsStore)
        .environmentObject(container.modelsViewModel)
}
