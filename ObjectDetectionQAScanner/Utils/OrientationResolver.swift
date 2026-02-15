import Foundation
import AVFoundation
import ImageIO
import CoreGraphics

/// カメラ接続情報（AVCapture）を Vision/EXIF 向きへ変換し、
/// 推論座標系の画像サイズも同じ規則で計算するユーティリティ。
enum OrientationResolver {
    /// 1フレーム分の向き情報をまとめて扱うための値オブジェクト。
    struct FrameOrientation {
        let videoOrientation: AVCaptureVideoOrientation
        let isMirrored: Bool
        let exifOrientation: CGImagePropertyOrientation
    }

    /// AVCaptureConnection の向き情報から、Vision が期待する EXIF 向きを解決する。
    /// - Parameters:
    ///   - videoOrientation: `connection.videoOrientation`
    ///   - isMirrored: `connection.isVideoMirrored`
    static func resolve(videoOrientation: AVCaptureVideoOrientation, isMirrored: Bool) -> FrameOrientation {
        let exifOrientation: CGImagePropertyOrientation

        switch videoOrientation {
        case .portrait:
            exifOrientation = isMirrored ? .leftMirrored : .right
        case .portraitUpsideDown:
            exifOrientation = isMirrored ? .rightMirrored : .left
        case .landscapeRight:
            exifOrientation = isMirrored ? .downMirrored : .up
        case .landscapeLeft:
            exifOrientation = isMirrored ? .upMirrored : .down
        @unknown default:
            exifOrientation = isMirrored ? .leftMirrored : .right
        }

        return FrameOrientation(
            videoOrientation: videoOrientation,
            isMirrored: isMirrored,
            exifOrientation: exifOrientation
        )
    }

    /// CVPixelBuffer の生サイズを、指定 EXIF 向きで解釈したときの見かけサイズへ変換する。
    /// Vision の decode/overlay で使う座標系は、ここで返す orientedImageSize に統一する。
    static func orientedImageSize(pixelWidth: Int, pixelHeight: Int, exifOrientation: CGImagePropertyOrientation) -> CGSize {
        let width = CGFloat(pixelWidth)
        let height = CGFloat(pixelHeight)

        switch exifOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width)
        case .up, .upMirrored, .down, .downMirrored:
            return CGSize(width: width, height: height)
        @unknown default:
            return CGSize(width: width, height: height)
        }
    }
}
