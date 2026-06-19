# New Native Performance Functions

This document records the native performance changes added to this source tree.

## Added Native Touch Tasks

The following task IDs were added in `pccontrol/Task.h` and handled in `pccontrol/Task.xm`.

| Task | Name | Format |
|---|---|---|
| `62` | `TASK_NATIVE_TAP` | `x;;y[;;duration_ms;;finger]` |
| `63` | `TASK_NATIVE_SWIPE` | `x1;;y1;;x2;;y2;;duration_ms[;;finger;;steps]` |
| `64` | `TASK_NATIVE_GESTURE` | `finger;;duration_ms;;x,y|x,y|...` |
| `65` | `TASK_NATIVE_BATCH` | `command||command`, each command starts with `10`, `62`, `63`, or `64` |

These commands execute inside SpringBoard, so gesture timing no longer depends on the PC sending every small `move` event over the network.

## Examples

Native tap:

```text
62120;;300;;50;;0\r\n
```

Native swipe:

```text
63100;;500;;100;;200;;300;;0;;20\r\n
```

Native gesture:

```text
640;;300;;100,500|120,450|160,400|200,350\r\n
```

Native batch:

```text
6562120;;300;;50;;0||63100;;500;;100;;200;;300;;0;;20\r\n
```

## Core Native Optimizations

- `pccontrol/Touch.xm`: removed `pow()` from the touch parser hot path and replaced it with fixed-digit integer parsing.
- `pccontrol/Touch.xm`: caches touch count once per event instead of recalculating it during the loop.
- `pccontrol/Touch.xm`: validates finger index before touching `eventsToAppend`.
- `pccontrol/Touch.xm`: throttles `senderID == 0` file logging to avoid writing logs for every touch event.

## Screenshot/Capture Optimizations

- `pccontrol/Screen.xm`: full-frame screenshot capture now skips an unnecessary `CGImageCreateWithImageInRect` crop.
- `pccontrol/Screen.xm`: screenshot output uses JPEG encoding automatically when the target path ends with `.jpg` or `.jpeg`; other paths keep the existing PNG behavior.

## IPC And Socket Optimizations

- `pccontrol/SocketResponder.xm`: `notifyClient` now writes until the whole response is sent and returns the correct byte count.
- `tlinkauto-binary/SocketServer.mm`: command TCP sockets now enable `TCP_NODELAY` for lower latency on small control packets.
- `tlinkauto-binary/SocketServer.mm`: IPC payload/success logs are suppressed for hot-path touch tasks `10`, `61`, `62`, `63`, `64`, and `65`.

## Daemon Routing

The daemon now routes task `62` to `65` to SpringBoard through the existing IPC path in `tlinkauto-binary/SocketServer.mm`.

## Recommended Usage

For PC control, prefer the new high-level commands:

```text
tap/swipe/gesture/batch
```

instead of streaming every `down/move/up` event individually. Use raw task `10` only when low-level control is required.

## Benchmark Scripts

Two benchmark scripts were added under `scripts/`.

PC-side latency benchmark:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite all --count 100 --json-out benchmark_pc.json
```

Useful PC-side modes:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite touch
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite gesture
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite screenshot
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite match
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite frame
```

The PC script measures round-trip latency for acknowledged tasks, send overhead for fire-and-forget task `10`, native gesture latency, screenshot latency, and optional JSON output.

Image/color match benchmark:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite match --match-count 50 --json-out benchmark_match.json --debug
```

The match suite always measures:

```text
task23_color_pick
task28_color_search_single
task28_color_is_colors
task28_color_find_multi_point
```

To also measure image matching, pass a template path that exists on the iOS device:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite match --template-path /var/mobile/Library/TLinkauto/Scripts/button.png --image-match-count 20 --match-region-x 0 --match-region-y 0 --match-region-w 0 --match-region-h 0 --json-out benchmark_match.json --debug
```

Image match benchmark measures both paths:

```text
task21_template_match_legacy
task49_find_image_cached_template
```

Useful match tuning flags:

```text
--match-acceptable 0.8
--match-scale-min 1.0
--match-scale-max 1.0
--match-scale-step 0.1
--match-pixel-skip 0
--color-x 120 --color-y 300
--color-region-x 0 --color-region-y 0 --color-region-w 0 --color-region-h 0
--color-tolerance 10
--color-skip 0
```

For cleaner CPU/RAM correlation, start `benchmark_ios_device.sh` on the iPhone before running the match suite from the PC.

## Manual Frame Lifecycle

Phase 2 adds manual frame lifecycle tasks for cached image/color checks. The default coordinate system is `pixel`, the pixel format is `BGRA`, and task `70` batches multiple checks on one frame to reduce IPC round-trips.

Defaults:

```text
coord_default= pixel
pixel_format = BGRA
max_frames = 3
default_ttl_ms = 1000
hard_ttl_ms = 5000
auto_cleanup = true
```

Task `66`: capture frame.

```text
66gray;;bgra;;ttl_ms
```

Example:

```text
661;;1;;1000\r\n
```

Response:

```text
0;;frame_id;;width;;height;;bytes_per_row;;scale;;coord;;pixel_format;;has_bgra;;has_gray;;created_at_ms;;capture_ms;;bgra_ms;;gray_ms;;total_ms
```

Task `67`: release frame.

```text
67frame_id
67all
```

Task `68`: find cached image object in frame.

```text
68frame_id;;image_id;;x;;y;;w;;h;;threshold;;scale_min;;scale_max;;scale_step;;pixel_skip;;coord;;max_age_ms
```

Response:

```text
0;;x;;y;;w;;h;;center_x;;center_y;;score;;frame_age_ms;;match_ms;;total_ms
```

Task `69`: color operation in frame.

```text
69frame_id;;pick;;x;;y;;coord;;max_age_ms
69frame_id;;pick_many;;x1,y1|x2,y2|x3,y3;;coord;;max_age_ms
69frame_id;;search_single;;x;;y;;w;;h;;rmin;;rmax;;gmin;;gmax;;bmin;;bmax;;skip;;coord;;max_age_ms
69frame_id;;is_colors;;table;;mode;;value;;coord;;max_age_ms
69frame_id;;find_multi_point;;x;;y;;w;;h;;table;;mode;;value;;skip;;coord;;max_age_ms
```

`pick_many` returns one field containing pipe-separated color results, then frame metrics:

```text
0;;x,y,r,g,b|x,y,r,g,b|...;;frame_age_ms;;scan_ms;;total_ms
```

Use `pick_many` when reading multiple pixels from the same frame. It avoids many repeated `69 pick` IPC round-trips.

Task `70`: batch frame checks.

```text
70frame_id;;op@@op@@op;;coord;;max_age_ms;;auto_release
```

Initial supported ops:

```text
img,image_id,x,y,w,h,acceptable,scale,pixel_skip
pick_many,x1:y1|x2:y2|x3:y3
```

Response:

```text
0;;op_result@@op_result@@op_result;;frame_age_ms;;native_total_ms
```

Image op result:

```text
img:x,y,w,h,center_x,center_y,score,match_ms
```

Color op result:

```text
pick_many:x,y,r,g,b|x,y,r,g,b|...,scan_ms
```

Use task `70` when a frame needs multiple image checks and color reads. It preserves the same frame lifecycle as tasks `68` and `69` but collapses multiple checks into one request. Set `auto_release=1` to release the frame inside task `70` after a successful batch, allowing the lifecycle `66 capture -> 70 batch` without a separate task `67` request.

Color reads use BGRA channel order internally:

```text
b = p[0]
g = p[1]
r = p[2]
a = p[3]
```

Frame benchmark:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite frame --frame-count 30 --scenario-count 10 --json-out benchmark_frame.json --debug
```

Frame benchmark with image matching:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite frame --template-path /var/mobile/Library/TLinkauto/scripts/button.png --image-match-count 20 --json-out benchmark_frame.json --debug
```

The frame benchmark reports native metrics when available:

```text
capture_avg_ms
bgra_avg_ms
gray_avg_ms
match_avg_ms
scan_avg_ms
native_total_avg_ms
ipc_overhead_est_avg_ms
```

Important scenarios:

```text
scenario_10_color_picks_old
scenario_10_color_picks_frame
scenario_10_color_picks_frame_many
scenario_2_image_5_color_old
scenario_2_image_5_color_frame
scenario_2_image_5_color_frame_many
scenario_fixed_frame_checks_only
scenario_fixed_frame_full_lifecycle
scenario_fixed_frame_batch_checks_only
scenario_fixed_frame_batch_full_lifecycle
```

`frame_many` scenarios use `pick_many` to reduce repeated task `69` requests.

Fixed-frame scenarios run in the frame suite when `--template-path` is set. They probe the template once, freeze a fixed pixel region with `--image-tune-fixed-pad`, then use `--fixed-scenario-image-count` task `68` checks and `--fixed-scenario-color-count` task `69 pick_many` color picks.

`scenario_fixed_frame_checks_only` measures checks on an already captured frame and excludes capture/release from `avg_ms`.

`scenario_fixed_frame_full_lifecycle` measures the full automation loop: capture one gray+BGRA frame, run fixed-region image checks, run `pick_many`, and release the frame.

`scenario_fixed_frame_batch_checks_only` and `scenario_fixed_frame_batch_full_lifecycle` run the same checks through task `70` to measure the IPC savings from batching. The full-lifecycle batch scenario uses `auto_release=1`, so it measures `66 capture -> 70 batch+release` instead of `66 -> 70 -> 67`.

Example:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite frame --template-path /var/mobile/Library/TLinkauto/scripts/button.png --image-tune-fixed-pad 50 --image-tune-fixed-skip 1 --image-tune-fixed-scale 1.0 --fixed-scenario-image-count 2 --fixed-scenario-color-count 5 --json-out benchmark_frame.json --debug
```

Fixed-frame output includes scope-specific metrics such as `capture_wall_avg_ms`, `release_wall_avg_ms`, `checks_total_avg_ms`, `image_match_total_avg_ms`, `image_match_each_avg_ms`, `image1_match_avg_ms`, `image2_match_avg_ms`, and `color_scan_avg_ms`.

Default automation lifecycle:

```text
Only color: 66 gray=0 bgra=1 -> 69 pick_many/is_colors/find_multi_point -> 67 release
Only image: 66 gray=1 bgra=0 -> 68 image checks -> 67 release
Image + color: 66 gray=1 bgra=1 -> 68 image checks -> 69 pick_many -> 67 release
Color precheck: 66 gray=1 bgra=1 -> 69 color precheck -> if pass then 68 image -> 67 release
```

Preferred automation lifecycle for image+color checks:

```text
66 gray=1 bgra=1 -> 70 img/pick_many ops with auto_release=1 -> tap/wait -> repeat
```

Use the non-batch lifecycle when you need an operation not yet supported by task `70`. For the current fixed-region path, task `70` is the default because it collapses repeated task `68` and task `69` IPC into one request and can release the frame without task `67`.

Python wrapper helper:

```python
ok, result = z.screen.batch_checks_auto_release(
    image_checks=[{
        "template": template,
        "region": (0, 2, 232, 236),
        "acceptable": 0.8,
        "scale": 1.0,
        "pixel_skip": 1,
    }],
    color_points=[(120, 300), (121, 300)],
)
```

Task70 scale benchmark:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite frame --template-path /var/mobile/Library/TLinkauto/scripts/button.png --image-tune-fixed-pad 50 --image-tune-fixed-skip 1 --image-tune-fixed-scale 1.0 --fixed-scenario-image-counts 1,2,3,5 --fixed-scenario-color-counts 0,5,10 --json-out benchmark_frame.json --debug
```

Scale benchmark rows use this name format:

```text
scenario_fixed_frame_batch_scale_i<image_count>_c<color_count>
```

## OCR / Text Recognition

OCR uses Apple's Vision framework (`VNRecognizeTextRequest`) through task `27`, and is supported on iOS 13 or newer. OCR is always routed to SpringBoard because Vision is more stable there.

Supported languages are not hardcoded. They are queried dynamically from the device:

```text
27 2;;level
```

`level` values:

```text
0 = accurate
1 = fast
```

Text recognition format:

```text
27 1;;x,,y,,w,,h;;custom_words;;minimum_height;;level;;languages;;correct;;debug_path
```

OCR benchmark:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite ocr --ocr-region-x 0 --ocr-region-y 0 --ocr-region-w 0 --ocr-region-h 0 --ocr-level both --ocr-count 5 --json-out benchmark_ocr.json --debug
```

Benchmark a small region with explicit languages:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite ocr --ocr-region-x 50 --ocr-region-y 200 --ocr-region-w 600 --ocr-region-h 300 --ocr-level fast --ocr-languages en-US,vi-VN --ocr-auto-correct 0 --ocr-count 5 --json-out benchmark_ocr.json --debug
```

OCR benchmark output includes:

```text
ocr_supported_languages_fast/accurate
ocr_fast_region_...
ocr_accurate_region_...
text_count_avg
chars_avg
last_ocr_result
```

OCR optimization guidance:

```text
Use the smallest practical region.
Prefer recognition_level=1 fast for automation checks.
Pass explicit languages such as en-US or vi-VN instead of leaving languages empty when possible.
Keep auto_correct=0 unless correction improves your specific target text.
Keep debug_image_path empty during benchmark and automation.
Let the device cool down before OCR benchmarks because Vision is CPU-heavy.
```

Native note: the default `minimum_height` now uses `1.0 / 32.0`; previously `1/32` evaluated to zero in native code.

### Task `91`: Tesseract OCR region in captured frame

Task `91` runs Tesseract OCR against a region from a frame created by task `66`. It must run in the same SpringBoard process that owns the frame cache, so the normal lifecycle is:

```text
66 capture gray=1 or bgra=1 -> 91 OCR region -> 67 release
```

Format:

```text
91frame_id;;x;;y;;w;;h;;lang;;oem;;psm;;whitelist_b64;;scale_up;;threshold_mode;;coord;;max_age_ms
```

Defaults for Vietnamese UI automation:

```text
lang=vie
fallback_lang=vie+eng
oem=1
psm=7
scale_up=2
threshold_mode=0
coord=pixel
max_age_ms=1000
```

Fields:

```text
lang = vie | eng | vie+eng
oem = 1 for LSTM-only
psm = 6 single_block, 7 single_line, 8 single_word
whitelist_b64 = optional UTF-8 whitelist encoded as base64
scale_up = 1..4, usually 2 for small mobile UI text
threshold_mode = 0 none, 1 binary/Otsu, 2 adaptive
coord = pixel or point
```

Response:

```text
0;;base64_text;;confidence;;frame_age_ms;;ocr_ms;;preprocess_ms;;total_ms
```

Error response:

```text
1;;error_code;;base64_message
```

Debug language check:

```text
91check_langs
```

Response data is:

```text
0;;check_langs;;base64_csv_languages
```

Tesseract data files are loaded from:

```text
/var/mobile/Library/TLinkauto/tessdata/vie.traineddata
/var/mobile/Library/TLinkauto/tessdata/eng.traineddata
```

Use `lang=vie` first for Vietnamese-only screens. Retry with `vie+eng` at the client level when the target text mixes English and Vietnamese or confidence is low.

PSM guidance:

```text
psm=7 single_line for labels/buttons/amounts
psm=8 single_word for one word or short code
psm=6 single_block for a small paragraph
```

Numeric OCR example uses a base64 whitelist for `0123456789.,%`:

```text
91frame_id;;x;;y;;w;;h;;vie;;1;;7;;MDEyMzQ1Njc4OS4sJQ==;;2;;1;;pixel;;1000
```

Benchmark Tesseract OCR immediately after MVP:

```text
ocr_tess_first_run
ocr_tess_warm_run
ocr_tess_vie_small_region
ocr_tess_vie_eng_small_region
ocr_tess_scale_1_2_3
ocr_tess_psm_6_7_8
ocr_tess_threshold_0_1_2
ocr_tess_whitelist_number
```

Track `preprocess_ms`, `ocr_ms`, `total_ms`, `text`, and `confidence`. First-run time should be reported separately because loading traineddata can be much slower than warm OCR.

Recommended usage for UI automation:

```text
Use coord=pixel by default with task 66 frames.
Use the smallest stable ROI that contains the text.
Use psm=7 for one label/button line.
Use psm=8 for one short word/code.
Use psm=6 only for a compact multi-line block.
Use lang=vie first; retry with vie+eng only when text mixes English and Vietnamese.
Keep threshold_mode=0 first; try 1 or 2 only when the background is noisy or contrast is poor.
Keep scale_up=2 first; try 3 only for very small text after ROI is correct.
```

Coordinate guidance:

Task `66` returns frame dimensions in pixels, for example an iPhone 6s can return `750x1334`. Because task `91` OCR runs on that captured pixel frame, `coord=pixel` avoids accidental scaling mistakes and is the recommended default. Use `coord=point` only when the caller intentionally passes UIKit point coordinates; the native handler will multiply by the captured frame scale.

Example: if the frame is `750x1334`, this pixel ROI reads a small label around the top-left app icons:

```sh
python scripts/debug_tesseract_ocr.py --host <iphone_ip> --check-langs --x 20 --y 100 --w 335 --h 120 --coord pixel --lang vie --psm 7 --scale-up 2 --threshold-mode 0
```

Typical output for a correct small ROI:

```text
text='Z Google'
confidence=87.04
ocr_ms=68.122
preprocess_ms=1.481
```

Large regions work but are slower and may include unrelated text/icons. For example `750x300` with `psm=6` can take around `300ms+` on an iPhone 6s, while a focused `335x120` single-line ROI can be around `70-100ms` warm-run. Prefer fixed, narrow regions in automation loops.

Bad OCR result patterns and fixes:

```text
Only symbols like "- - | `" -> ROI is probably wrong, too high/low, or using point when pixel was intended.
Text contains many unrelated app names -> ROI is too large; shrink it before tuning threshold or language.
Confidence low but ROI is correct -> try threshold_mode=1, then scale_up=3, then lang=vie+eng.
Numeric/OTP/money text unstable -> use psm=7 and a whitelist such as 0123456789.,%.
```

Recommended tuning order:

```text
1. Confirm languages with 91check_langs.
2. Capture one frame and note pixel size.
3. Find the correct pixel ROI with a larger region.
4. Shrink ROI until it contains only target text.
5. Choose psm=7/8/6 based on layout.
6. Try scale_up=2, then 3 only if text is small.
7. Try threshold_mode=1 or 2 only after ROI and PSM are correct.
8. Add whitelist for numeric/code targets.
9. Benchmark first-run and warm-run separately.
```

Debug helper:

```sh
python scripts/debug_tesseract_ocr.py --host <iphone_ip> --check-langs --x 20 --y 100 --w 335 --h 120 --coord pixel --lang vie --psm 7 --scale-up 2 --threshold-mode 0 --count 5
```

The debug script prints decoded text, confidence, `frame_age_ms`, `ocr_ms`, `preprocess_ms`, native total time, socket roundtrip time, and always releases the captured frame.

Image tuning benchmark:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite image-tune --template-path /var/mobile/Library/TLinkauto/scripts/button.png --json-out benchmark_image_tune.json --debug
```

Useful image tuning flags:

```text
--image-tune-count 5
--image-tune-regions full,50%,25%,custom,found_pad_100
--image-tune-skips 0,1,2,3,4
--image-tune-scales 1.0
--image-tune-fixed-pad 50
--image-tune-fixed-skip 1
--image-tune-fixed-scale 1.0
```

`image-tune` captures and releases a fresh frame for each `region + skip + scale` config so large tuning matrices do not outlive the native frame TTL.

Custom region uses `--match-region-x/y/w/h`:

```sh
python scripts/benchmark_pc_tlinkauto.py --host <iphone_ip> --suite image-tune --template-path /var/mobile/Library/TLinkauto/scripts/button.png --match-region-x 100 --match-region-y 600 --match-region-w 500 --match-region-h 300 --image-tune-regions custom --image-tune-skips 0,1,2,3,4 --json-out benchmark_image_tune.json --debug
```

Named region format:

```text
--image-tune-regions full,button:100/600/500/300
```

Auto region around the real full-screen match:

```text
--image-tune-regions full,found_pad_50,found_pad_100,found_pad_200
```

`found_pad_N` runs one full-screen probe first, then builds a pixel region around the matched template box with `N` pixels of padding. Percent regions such as `50%` and `25%` are centered regions, so they can miss templates outside the screen center.

Practical fixed-region scenario:

```text
scenario_image_fixed_region_capture_match
```

This scenario runs after the tuning matrix when the full-screen probe finds the template. It freezes a pixel region from the probe result using `--image-tune-fixed-pad`, then measures the real loop: capture frame, run task `68` in the fixed region, release frame. Use `--image-tune-fixed-skip` and `--image-tune-fixed-scale` for the fixed-region check. For the current button benchmark, `--image-tune-fixed-pad 50 --image-tune-fixed-skip 1 --image-tune-fixed-scale 1.0` is the recommended starting point.

Image tuning output includes:

```text
region_pixels
pixel_skip
scale_min/scale_max
match_avg_ms
found_rate
score_avg/score_min/score_max
```

Use this benchmark before changing SAD logic. Prefer the smallest stable region, fixed scale `1.0`, and the largest `pixel_skip` that keeps `found_rate` and score stable.

Recommended lifecycle in automation:

```text
1. 66 capture frame
2. 68/69 run image/color checks on the same frame_id
3. 67 release frame
4. tap/wait
5. capture the next frame
```

iOS-side CPU/RAM sampler:

```sh
sh scripts/benchmark_ios_device.sh 120 1 /var/mobile/Library/TLinkauto/benchmark_ios.csv
```

Arguments:

```text
benchmark_ios_device.sh <duration_seconds> <interval_seconds> <output_csv> [process_names]
```

Example with custom processes:

```sh
sh scripts/benchmark_ios_device.sh 120 1 /var/mobile/Library/TLinkauto/benchmark_ios.csv "SpringBoard tlinkautod"
```

Recommended test flow:

```text
1. Start benchmark_ios_device.sh on the iPhone.
2. Run benchmark_pc_tlinkauto.py from the PC while the iOS sampler is running.
3. Compare task10 raw touch vs task62 native tap, streamed moves vs task63/task64 native gestures, and PNG vs JPG screenshot latency.
```
