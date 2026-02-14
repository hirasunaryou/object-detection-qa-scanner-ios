# ObjectDetectionQAScanner (iOS MVP)

CoreMLベースのカスタム物体検知モデルを、iPhone上でライブ推論しながら安定性評価・ログ保存・レポート集計・ZIPエクスポートまで実施するMVPです。

## 要件
- iOS 16+
- Xcode 16+
- SwiftUI / AVFoundation / CoreML / Vision

## 機能
- **Live**: 背面カメラのライブ推論、BBox表示、stable判定、確定/NGログ保存
- **Models**: モデルZIPのインポート、コンパイル、アクティブ切り替え、閾値設定
- **Reports**: モデル別の集計表示、ログ+画像ZIPエクスポート

## モデルZIP形式
ZIP直下に以下を配置してください。

- `model.mlmodel` または `model.mlpackage`
- `metadata.json`

`metadata.json` 例:

```json
{
  "model_id": "yolov8n_2026_02_14",
  "display_name": "YOLOv8n QA 2026-02-14",
  "created_at": "2026-02-14T10:00:00Z",
  "classes": ["box", "seal", "damage"]
}
```

## 使い方
1. アプリ起動後、`Models` タブでZIPをインポート
2. 必要に応じて `confThreshold` / `stableFramesRequired` / `minBoxAreaRatio` を調整
3. `Live` タブで推論を実施
4. stable時のみ「開封する（確定）」が有効
5. NGの場合は理由を選択して保存
6. `Reports` タブで集計確認、`Export ZIP` で共有

## ビルド手順
1. Xcodeで `ObjectDetectionQAScanner.xcodeproj` を開く
2. Signing Team/Bundler IDを自身の設定に変更
3. 実機を選択してビルド＆実行
4. 初回起動時にカメラ権限を許可

## 保存先
- モデル: `Documents/models/`
- ログ: `Documents/scan_logs/events.jsonl`
- 画像: `Documents/scan_logs/images/`

## テスト手順（手動）
- モデルを切り替えて推論が継続するか
- 単一検知・高信頼時にstable到達するか
- ラベル変化/検知ロストでflicker増加するか
- 確定/NG押下でJSONLと画像が保存されるか
- Export ZIPの中にログと画像が入っているか
