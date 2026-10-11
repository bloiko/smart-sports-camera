# Results

Living document. Add a row for every new model or pipeline version, per match. Definitions of the metrics are in `../docs/testing-strategy.md`.

Last updated: 2026-10-11

## Tracker metrics (`follow.py` → `metrics.json`)

`ball found` = share of sampled frames where the tracker accepted a ball. `in crop` = share of those frames where the ball is inside the output crop. `players` = average share of on-field players inside the crop.

| Date | Version | Match | Ball search | Ball found | In crop | Players | Max pan px/s |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-10-10 | v0.1 | 1 | Panorama tiles, YOLO11s | 12.7% | 94.1% | 71.6% | 363 |
| 2026-10-10 | v0.2-a | 1 | + 2× window, YOLO11s | 20.7% | 95.2% | 70.8% | 367 |
| 2026-10-10 | v0.2 | 1 | + 2× window, `ball_v02.pt` | 29.6% | 98.3% | 70.2% | 391 |
| 2026-10-10 | v0.2 | 2 | Panorama tiles only | 45.3% | 99.3% | 66.7% | 288 |
| 2026-10-10 | v0.2 | 2 | + window, YOLO11s | 55.5% | 99.7% | 66.0% | — |
| 2026-10-10 | v0.2 | 2 | + window, YOLO11s ∪ `ball_v02.pt` | **65.9%** | 100% | 65.6% | — |
| 2026-10-11 | v0.2 | 3 | Panorama tiles only | 15.3% | 94.6% | 72.5% | 350 |
| 2026-10-11 | v0.2 | 3 | + window, YOLO11s | 16.1% | 94.8% | 72.3% | — |
| 2026-10-11 | v0.2 | 3 | + window, `ball_v02.pt` | 25.3% | 96.1% | 72.4% | — |
| 2026-10-11 | v0.2 | 3 | + window, YOLO11s ∪ `ball_v02.pt` | **25.6%** | 96.1% | 72.3% | — |

## Raw detector comparison (ball in window, excluding static spare balls)

| Match | Frames | YOLO11s (conf ≥ 0.25) | `ball_v02.pt` (conf ≥ 0.4) | Note |
| --- | --- | --- | --- | --- |
| 1, held-out last 20% | 240 | 19.2% | 40.4% | v0.2 trained on the first 80% of this match |
| 2 | 596 | 58.7% | 51.7% | v0.2 overfitted to match 1 |

## Precision spot-checks

| Date | Match | Version | Result |
| --- | --- | --- | --- |
| 2026-10-10 | 2 | union | 12 of 12 accepted detections were the real ball |
| 2026-10-11 | 3 | union | 11 of 12 (one false detection on a fence) |

## Goal checklist

| Match | Goal / shot (time) | Visible in output? | Version |
| --- | --- | --- | --- |
| 1 | Goal between 2:00 and 4:00 (exact time to be filled in) | **No**, reported by the owner | v0.2 |
