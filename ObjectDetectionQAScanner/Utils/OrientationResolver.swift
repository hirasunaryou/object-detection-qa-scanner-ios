import Foundation
import AVFoundation
import ImageIO

/// カメラ接続の向き(AVCapture)を Vision の EXIF 向きへ変換し、
/// 推論・描画・保存の座標系を1フレーム単位で一致させるユーティリティ。
enum OrientationResolver {
    static func exifOrientation(
        videoOrientation: AVCaptureVideoOrientation,
        isMirrored: Bool
    ) -> CGImagePropertyOrientation {
        switch (videoOrientation, isMirrored) {
        case (.portrait, false):
            return .right
        case (.portrait, true):
            return .leftMirrored
        case (.portraitUpsideDown, false):
            return .left
        case (.portraitUpsideDown, true):
            return .rightMirrored
        case (.landscapeRight, false):
            return .down
        case (.landscapeRight, true):
            return .upMirrored
        case (.landscapeLeft, false):
            return .up
        case (.landscapeLeft, true):
            return .downMirrored
        @unknown default:
            return .right
        }
    }

    static func orientedImageSize(
        pixelBufferWidth: Int,
        pixelBufferHeight: Int,
        exifOrientation: CGImagePropertyOrientation
    ) -> CGSize {
        if exifOrientation.swapsWidthAndHeight {
            return CGSize(width: pixelBufferHeight, height: pixelBufferWidth)
        }
        return CGSize(width: pixelBufferWidth, height: pixelBufferHeight)
    }
}

private extension CGImagePropertyOrientation {
    var swapsWidthAndHeight: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        case .up, .upMirrored, .down, .downMirrored:
            return false
        @unknown default:
            return false
        }
    }
}
