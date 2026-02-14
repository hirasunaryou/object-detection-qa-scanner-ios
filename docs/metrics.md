# Stability Metrics 定義

## Stable 判定条件
1. 検知数が 1 (`allowMultipleDetections=false` の場合)
2. `confidence >= confThreshold`
3. `bbox_area_ratio >= minBoxAreaRatio`
4. `IoU(prev_bbox, curr_bbox) >= 0.7`

上記を **`stableFramesRequired` 連続フレーム**で満たしたら stable。

## 指標
- `scan_count`: モデルごとのログ件数
- `success_count`: confirm 件数
- `success_rate = success_count / scan_count`
- `avg_time_to_stable`: stable 到達までの平均秒数
- `avg_flicker`: stable 到達までの平均 flicker 数
- `multi_detection_rate`: 複数検知フレームを含むログ比率

## flicker_count の定義
stable 到達までに起きた以下イベントの累積:
- ラベル変化
- 検知消失（no detection）

## IoU
\[
IoU = \frac{|A \cap B|}{|A \cup B|}
\]
- A: 前フレーム bbox
- B: 現フレーム bbox
