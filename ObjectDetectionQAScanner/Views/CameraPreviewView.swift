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
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}

struct DetectionOverlayView: View {
    let detections: [Detection]
    let sourceImageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            // Vision座標は orientation適用後の画像空間を基準にするため、
            // .right 指定時は width/height を入れ替えた portrait 空間で扱います。
            let orientedSourceSize = CGSize(width: sourceImageSize.height, height: sourceImageSize.width)
            let scale = max(
                geo.size.width / max(orientedSourceSize.width, 1),
                geo.size.height / max(orientedSourceSize.height, 1)
            )
            let displayedWidth = orientedSourceSize.width * scale
            let displayedHeight = orientedSourceSize.height * scale
            let xOffset = (geo.size.width - displayedWidth) / 2
            let yOffset = (geo.size.height - displayedHeight) / 2

            ForEach(detections) { det in
                let rect = CGRect(
                    x: xOffset + det.boundingBox.minX * displayedWidth,
                    y: yOffset + (1 - det.boundingBox.maxY) * displayedHeight,
                    width: det.boundingBox.width * displayedWidth,
                    height: det.boundingBox.height * displayedHeight
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
