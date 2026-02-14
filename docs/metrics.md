# Stability Metrics

## 判定条件（フレーム単位）
- `detection count == 1`（`allowMultipleDetections=false` のとき）
- `confidence >= confThreshold`
- `bbox area ratio >= minBoxAreaRatio`
- `IoU(prev_bbox, curr_bbox) >= 0.7`

## stable の定義
上記条件を **連続 `stableFramesRequired` フレーム** 満たすと stable。

## flicker_count
stable到達前に以下が起こるたびに +1。
- ラベルが変わる
- 検知が消える

## レポート指標
- `scan_count`: 全スキャン数
- `success_count`: 確定成功数
- `success_rate`: `success_count / scan_count`
- `avg_time_to_stable`: 成功時の stable到達時間平均(ms)
- `avg_flicker`: flickerの平均
- `multi_detection_rate`: 複数検知が発生した割合
