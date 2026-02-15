import SwiftUI

struct LiveView: View {
    private let previewCornerRadius: CGFloat = 14

    @ObservedObject var viewModel: LiveViewModel

    @State private var selectedNGReason: NGReason = .other
    @State private var message = ""
    @State private var isDebugPanelExpanded = true

    var body: some View {
        VStack(spacing: 12) {
            previewSection

            Text(viewModel.isStable ? "Stable ✅" : "Not stable")
                .font(.headline)
                .foregroundStyle(viewModel.isStable ? .green : .orange)

            Text(viewModel.modelStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            actionSection

            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Subviews

    /// プレビュー/オーバーレイ/デバッグ情報を一箇所にまとめることで、
    /// `body` の責務を「画面構成の説明」に絞って読みやすくする。
    private var previewSection: some View {
        ZStack(alignment: .topLeading) {
            CameraPreviewView(session: viewModel.cameraManager.session)
                .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))
            DetectionOverlayView(detections: viewModel.detections, imageSize: viewModel.inferenceImageSize)
                .clipShape(RoundedRectangle(cornerRadius: previewCornerRadius))

            debugPanel
        }
    }

    /// ユーザー操作（確定/NG）を分離し、今後ボタン追加があってもここだけで追えるようにする。
    private var actionSection: some View {
        HStack {
            Button("開封する（確定）") {
                saveConfirm()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isStable)

            Picker("NG", selection: $selectedNGReason) {
                ForEach(NGReason.allCases) { reason in
                    Text(reason.rawValue).tag(reason)
                }
            }

            Button("NG") {
                saveNG()
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Live画面のオーバーレイは視認性が重要なので、
            // デバッグ情報は展開・折りたたみを切り替え可能にして邪魔になりにくくする。
            HStack(spacing: 8) {
                Label("Debug", systemImage: "ladybug")
                    .fontWeight(.semibold)

                Spacer(minLength: 8)

                Button {
                    isDebugPanelExpanded.toggle()
                } label: {
                    Image(systemName: isDebugPanelExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDebugPanelExpanded ? "デバッグ情報を折りたたむ" : "デバッグ情報を展開する")
            }

            if isDebugPanelExpanded {
                Label("Inference FPS: \(viewModel.fps, specifier: "%.1f")", systemImage: "speedometer")
                Label("Inference Latency: \(viewModel.latencyMs, specifier: "%.1f") ms", systemImage: "timer")
                Text(viewModel.inferenceDebugText)
                Text("Reason: \(viewModel.stableReason)")
                Text("Flicker: \(viewModel.flickerCount)")
            }
        }
        .font(.caption)
        .padding(8)
        .background(.black.opacity(0.5))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }

    // MARK: - Actions

    private func saveConfirm() {
        do {
            try viewModel.saveConfirm()
            message = "確定を保存しました"
        } catch {
            message = error.localizedDescription
        }
    }

    private func saveNG() {
        do {
            try viewModel.saveNG(reason: selectedNGReason)
            message = "NGを保存しました"
        } catch {
            message = error.localizedDescription
        }
    }
}
