import SwiftUI

struct LiveView: View {
    @ObservedObject var viewModel: LiveViewModel

    @State private var selectedNGReason: NGReason = .other
    @State private var message = ""

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                CameraPreviewView(session: viewModel.cameraManager.session)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                DetectionOverlayView(detections: viewModel.detections, imageSize: viewModel.inferenceImageSize)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Inference FPS: \(viewModel.fps, specifier: "%.1f")", systemImage: "speedometer")
                    Label("Inference Latency: \(viewModel.latencyMs, specifier: "%.1f") ms", systemImage: "timer")
                    Text(viewModel.inferenceDebugText)
                    Text("Reason: \(viewModel.stableReason)")
                    Text("Flicker: \(viewModel.flickerCount)")
                }
                .font(.caption)
                .padding(8)
                .background(.black.opacity(0.5))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(8)
            }

            Text(viewModel.isStable ? "Stable ✅" : "Not stable")
                .font(.headline)
                .foregroundStyle(viewModel.isStable ? .green : .orange)

            Text(viewModel.modelStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("開封する（確定）") {
                    do {
                        try viewModel.saveConfirm()
                        message = "確定を保存しました"
                    } catch {
                        message = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isStable)

                Picker("NG", selection: $selectedNGReason) {
                    ForEach(NGReason.allCases) { reason in
                        Text(reason.rawValue).tag(reason)
                    }
                }

                Button("NG") {
                    do {
                        try viewModel.saveNG(reason: selectedNGReason)
                        message = "NGを保存しました"
                    } catch {
                        message = error.localizedDescription
                    }
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)

            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}
