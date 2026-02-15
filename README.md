# ObjectDetectionQAScanner (iOS MVP)

SwiftUI + AVFoundation + CoreML/Vision で、iPhone 上でカスタム物体検知モデルのライブ QA を行うための MVP です。

## 対応
- iOS 16+
- Xcode 16+

## 主な機能
- **Live**: 背面カメラプレビュー / bbox オーバーレイ / stable判定 / 確定・NGログ保存 / FPS・Latency表示
- **Models**: モデル切替、ZIPインポート、推論閾値などの設定
- **Reports**: モデル別メトリクス集計、ログ+画像フォルダの共有

## プロジェクト構成（MVVM）
- `CameraManager`（AVCaptureVideoDataOutput）
- `InferenceEngine`（Vision + CoreML）
- `StabilityEvaluator`（状態機械）
- `LogStore`（JSONL）
- `Exporter`（共有用ディレクトリ生成）

## ビルド手順
1. Xcode で `ObjectDetectionQAScanner.xcodeproj` を開く
2. Signing Team を設定
3. 実機（iPhone）を選択して Build & Run
4. 初回起動時のカメラ許可を許可

## モデル ZIP 形式
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
1. Models タブで ZIP を import
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


## いま出来ること（重要）
- ✅ Live: カメラ表示 / stable判定 / 確定・NGの保存 / ログ・画像の共有
- ✅ Models: モデルZIP import / モデル切替 / 安定判定パラメータ調整

## データの保存場所
- Application Support / QAData/
  - scan_logs.jsonl
  - images/（raw/overlay）

## エクスポート手順（現場向け）
1. Reports → 「ログと画像フォルダを共有」
2. AirDrop / Files / Drive などでPCに転送
3. PC側で scan_logs.jsonl と images/ を確認
