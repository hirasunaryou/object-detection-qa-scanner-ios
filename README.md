# ObjectDetectionQAScanner (iOS MVP)

SwiftUI + AVFoundation + CoreML/Vision で、iPhone 上でカスタム物体検知モデルのライブ QA を行うための MVP です。

## 対応
- iOS 16+
- Xcode 16+

## 主な機能
- **Live**: 背面カメラプレビュー / bbox オーバーレイ / stable判定 / 確定・NGログ保存 / FPS・Latency表示
- **Models**: モデル切替、推論閾値などの設定（※ZIPインポートは一時停止中）
- **Reports**: モデル別メトリクス集計、ログ+画像フォルダの共有

## プロジェクト構成（MVVM）
- `CameraManager`（AVCaptureVideoDataOutput）
- `InferenceEngine`（Vision + CoreML）
- `StabilityEvaluator`（状態機械）
- `LogStore`（JSONL）
- `Exporter`（ZIP）

## ビルド手順
1. Xcode で `ObjectDetectionQAScanner.xcodeproj` を開く
2. Signing Team を設定
3. 実機（iPhone）を選択して Build & Run
4. 初回起動時のカメラ許可を許可

## モデル ZIP 形式（将来有効化予定）
ZIP のルート直下に以下を配置してください。
- `model.mlmodel` または `model.mlpackage`
- `metadata.json`

`metadata.json` 例:

```json
{
  "model_id": "yolov8n_custom_2026_02_14",
  "display_name": "YOLOv8n Custom 2026-02-14",
  "created_at": "2026-02-14T00:00:00Z",
  "classes": ["box", "opened_box", "damaged"]
}
```

## QA操作フロー
1. （将来）Models タブで ZIP を import
2. `Use` でアクティブモデル化
3. Live タブで対象を撮影
4. Stable になったら「開封する（確定）」が有効化
5. 必要時は NG 理由を選んで `NG`
6. Reports タブで集計確認、ログフォルダ共有

## テスト手順
- 実機で Live 推論が動作するか
- stable 条件を満たした時のみ確定ボタン有効化されるか
- NG 保存時に JSONL と画像が増えるか
- Reports 集計値の計算が妥当か
- ログフォルダ共有が ShareSheet で開けるか

## 注意
- 物体検知の出力は `VNRecognizedObjectObservation` を想定しています。
- モデル変換時は CoreML でオブジェクト検知として扱える形式にしてください。
