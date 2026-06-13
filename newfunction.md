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
