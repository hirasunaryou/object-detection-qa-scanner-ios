import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        TabView {
            LiveView(viewModel: LiveViewModel(container: container))
                .tabItem { Label("Live", systemImage: "camera.viewfinder") }

            ModelsView(viewModel: ModelsViewModel(container: container))
                .tabItem { Label("Models", systemImage: "cube.box") }

            ReportsView(viewModel: ReportsViewModel(container: container))
                .tabItem { Label("Reports", systemImage: "chart.bar.xaxis") }
        }
    }
}
