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
- `zxtouch-binary/SocketServer.mm`: command TCP sockets now enable `TCP_NODELAY` for lower latency on small control packets.
- `zxtouch-binary/SocketServer.mm`: IPC payload/success logs are suppressed for hot-path touch tasks `10`, `61`, `62`, `63`, `64`, and `65`.

## Daemon Routing

The daemon now routes task `62` to `65` to SpringBoard through the existing IPC path in `zxtouch-binary/SocketServer.mm`.

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
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite all --count 100 --json-out benchmark_pc.json
```

Useful PC-side modes:

```sh
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite touch
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite gesture
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite screenshot
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite match
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite frame
```

The PC script measures round-trip latency for acknowledged tasks, send overhead for fire-and-forget task `10`, native gesture latency, screenshot latency, and optional JSON output.

Image/color match benchmark:

```sh
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite match --match-count 50 --json-out benchmark_match.json --debug
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
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite match --template-path /var/mobile/Library/ZXTouch/Scripts/button.png --image-match-count 20 --match-region-x 0 --match-region-y 0 --match-region-w 0 --match-region-h 0 --json-out benchmark_match.json --debug
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

Phase 2 adds manual frame lifecycle tasks for cached image/color checks. The default coordinate system is `pixel`, the pixel format is `BGRA`, and task `70` batch is intentionally deferred.

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
69frame_id;;search_single;;x;;y;;w;;h;;rmin;;rmax;;gmin;;gmax;;bmin;;bmax;;skip;;coord;;max_age_ms
69frame_id;;is_colors;;table;;mode;;value;;coord;;max_age_ms
69frame_id;;find_multi_point;;x;;y;;w;;h;;table;;mode;;value;;skip;;coord;;max_age_ms
```

Color reads use BGRA channel order internally:

```text
b = p[0]
g = p[1]
r = p[2]
a = p[3]
```

Frame benchmark:

```sh
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite frame --frame-count 30 --scenario-count 10 --json-out benchmark_frame.json --debug
```

Frame benchmark with image matching:

```sh
python scripts/benchmark_pc_zxtouch.py --host <iphone_ip> --suite frame --template-path /var/mobile/Library/ZXTouch/scripts/button.png --image-match-count 20 --json-out benchmark_frame.json --debug
```

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
sh scripts/benchmark_ios_device.sh 120 1 /var/mobile/Library/ZXTouch/benchmark_ios.csv
```

Arguments:

```text
benchmark_ios_device.sh <duration_seconds> <interval_seconds> <output_csv> [process_names]
```

Example with custom processes:

```sh
sh scripts/benchmark_ios_device.sh 120 1 /var/mobile/Library/ZXTouch/benchmark_ios.csv "SpringBoard zxtouchd"
```

Recommended test flow:

```text
1. Start benchmark_ios_device.sh on the iPhone.
2. Run benchmark_pc_zxtouch.py from the PC while the iOS sampler is running.
3. Compare task10 raw touch vs task62 native tap, streamed moves vs task63/task64 native gestures, and PNG vs JPG screenshot latency.
```
