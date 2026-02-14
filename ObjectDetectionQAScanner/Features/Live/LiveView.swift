import SwiftUI

struct LiveView: View {
    @StateObject var viewModel: LiveViewModel

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                CameraPreviewView(session: viewModel.container.cameraManager.session)
                    .frame(maxWidth: .infinity, maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                DetectionOverlayView(detections: viewModel.detections)
            }

            HStack {
                Text(viewModel.fpsText)
                Spacer()
                Text(viewModel.latencyText)
            }
            .font(.caption)

            Text(viewModel.infoText)
                .font(.headline)

            HStack {
                Button("開封する（確定）") {
                    viewModel.confirmOpen()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.stableState.isStable)

                Menu("NG") {
                    ForEach(NGReason.allCases) { reason in
                        Button(reason.rawValue) {
                            viewModel.markNG(reason: reason)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }
}

private struct DetectionOverlayView: View {
    let detections: [DetectionResult]

    var body: some View {
        GeometryReader { geo in
            ForEach(detections) { detection in
                let rect = CGRect(
                    x: detection.boundingBox.minX * geo.size.width,
                    y: (1 - detection.boundingBox.maxY) * geo.size.height,
                    width: detection.boundingBox.width * geo.size.width,
                    height: detection.boundingBox.height * geo.size.height
                )
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .path(in: rect)
                        .stroke(Color.green, lineWidth: 2)
                    Text("\(detection.label) \(Int(detection.confidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.7))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
    }
}
