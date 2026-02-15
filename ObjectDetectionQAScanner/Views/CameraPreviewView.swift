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
        // プレビューの見た目と推論の座標系を揃えるため、表示向きも portrait 固定にする。
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}

struct DetectionOverlayView: View {
    let detections: [Detection]
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            ForEach(detections) { det in
                let rect = rectInPreview(
                    normalizedRect: det.boundingBox,
                    imageSize: imageSize,
                    previewSize: geo.size
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

    private func rectInPreview(normalizedRect: CGRect, imageSize: CGSize, previewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, previewSize.width > 0, previewSize.height > 0 else {
            return CGRect(
                x: normalizedRect.minX * previewSize.width,
                y: (1 - normalizedRect.maxY) * previewSize.height,
                width: normalizedRect.width * previewSize.width,
                height: normalizedRect.height * previewSize.height
            )
        }

        // Vision座標(左下原点)を画像ピクセル座標(左上原点)へ変換。
        let imageRect = CGRect(
            x: normalizedRect.minX * imageSize.width,
            y: (1 - normalizedRect.maxY) * imageSize.height,
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )

        // プレビューは resizeAspectFill のため、表示時の拡大率とトリミング量を反映して重ねる。
        let scale = max(previewSize.width / imageSize.width, previewSize.height / imageSize.height)
        let scaledImageSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let xOffset = (previewSize.width - scaledImageSize.width) * 0.5
        let yOffset = (previewSize.height - scaledImageSize.height) * 0.5

        return CGRect(
            x: imageRect.minX * scale + xOffset,
            y: imageRect.minY * scale + yOffset,
            width: imageRect.width * scale,
            height: imageRect.height * scale
        )
    }
}
