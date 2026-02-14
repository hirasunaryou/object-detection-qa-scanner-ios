import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.videoGravity = .resizeAspectFill
    }
}

struct DetectionOverlayView: View {
    let detections: [Detection]

    var body: some View {
        GeometryReader { geo in
            ForEach(detections) { det in
                let rect = CGRect(
                    x: det.boundingBox.minX * geo.size.width,
                    y: (1 - det.boundingBox.maxY) * geo.size.height,
                    width: det.boundingBox.width * geo.size.width,
                    height: det.boundingBox.height * geo.size.height
                )
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(.green, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                    Text("\(det.label) \(String(format: "%.2f", det.confidence))")
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .offset(y: -20)
                }
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }
}
