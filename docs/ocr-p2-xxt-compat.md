# OCR P2 XXTouch-Compatible Vision Canary

## Scope

P2 adds the opt-in task `27` profile `xxt_compat`. It intentionally mirrors
the Apple OCR path recovered from XXTouch's `libxxtouch.so`:

- construct `VNRecognizeTextRequest` with plain `init`;
- redraw the cropped image into compact BGRA8888 premultiplied-first
  (`bytesPerRow = width * 4`, `bitmapInfo = 0x2002`) and pass that `CGImage`
  directly to `VNImageRequestHandler`;
- call `performRequests:error:` synchronously;
- leave compute-device selection to Vision (no `usesCPUOnly`);
- default to `en-US` when no language was supplied.

The existing `app_cpu` default, opt-in `worker_cpu`, task `27` response bytes,
and production task `91` Tesseract path are unchanged. Following the device
crash report from 2026-08-29, `xxt_compat` now performs Vision in the foreground
`StreamControl.app` process through localhost port `6011`. The isolated worker
still captures and crops the image, but no longer calls Vision. This avoids the
headless root worker's crash in `CI::GLContext::GLContext`.

`StreamControl` must be open and active for this canary. Background requests
return `app_ocr_requires_foreground`. The app redraws the bridged PNG as compact
BGRA `0x2002`, uses a plain request with automatic compute selection, and runs
it on a dedicated serial queue. Concurrent requests return `app_ocr_busy`; a
15-second watchdog returns a bounded timeout.

## First Device Test

Use a small region and Fast recognition for the first request after installing
the build. Open `StreamControl` and leave it visible while running the command:

```powershell
./scripts/Collect-TLinkOCRBaseline.ps1 `
  -HostIP "192.168.1.244" `
  -TimeoutMs 30000 `
  -Context foreground `
  -RunVision `
  -VisionProfile xxt_compat `
  -RecognitionLevel 1 `
  -RegionX 0 `
  -RegionY 0 `
  -RegionWidth 320 `
  -RegionHeight 160 `
  -VisionLanguages en-US `
  -SkipTesseract `
  -ClearVisionDebugLog `
  -Notes "fresh launch; first xxt_compat request"
```

The command writes `ocr-baseline-<timestamp>/ocr-baseline.json`. Inspect these
fields:

- `probes.task27_vision.response`
- `probes.task27_vision.roundtrip_ms`
- `probes.task27_debug_after.decoded_log`
- `probes.task97_postflight`

Do not test Accurate or a larger region until this Fast request returns a
bounded result.

## Direct PowerShell Probe

For a quick probe without the collector, use this complete function in the
same PowerShell window:

```powershell
function Invoke-TLinkTask {
    param([string]$HostIP, [string]$Task, [int]$Port = 6000, [int]$TimeoutMs = 30000)
    $client = [Net.Sockets.TcpClient]::new()
    $client.ReceiveTimeout = $TimeoutMs
    $client.SendTimeout = $TimeoutMs
    try {
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false), 1024, $true)
        $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false), $false, 4096, $true)
        $writer.NewLine = "`r`n"
        $writer.AutoFlush = $true
        $writer.WriteLine($Task)
        $reader.ReadLine()
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($writer) { $writer.Dispose() }
        if ($stream) { $stream.Dispose() }
        $client.Dispose()
    }
}

$iphoneIP = "192.168.1.244"
Invoke-TLinkTask -HostIP $iphoneIP -Task "274"                  # clear debug log
Invoke-TLinkTask -HostIP $iphoneIP -Task "271;;0,,0,,320,,160;;;;0.03125;;1;;en-US;;0;;;;xxt_compat"
$raw = Invoke-TLinkTask -HostIP $iphoneIP -Task "273"
$parts = $raw.Split(@(";;"), [StringSplitOptions]::None)
if ($parts.Count -ge 3 -and $parts[0] -eq "0" -and $parts[1] -eq "vision_debug_base64") {
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[2]))
} else {
    $raw
}
```

Task `273` returns the last 64 KiB of
`/var/mobile/Library/TLinkauto/runtime/vision-ocr-debug.log` as Base64. Task
`274` clears that file. Neither task invokes Vision.

The app and worker use bridge protocol v2. It carries minimum text height,
recognition level, custom words, languages, language correction, and profile
without changing task `27`'s public wire format.

## Interpreting Results

| Last phase or response | Meaning |
|---|---|
| `app_response_ready` and `0;;...` | Vision completed and task `27` produced a valid legacy response. |
| `app_perform_failed` | Vision returned an `NSError`; retain its domain, code, and text. |
| `app_ocr_requires_foreground` | Open StreamControl and keep it active during the probe. |
| `app_ocr_timeout timeout_ms=15000` | Vision blocked; restart StreamControl before retrying. |
| `app_ocr_busy` | A previous Vision operation is still running in the app queue. |
| No `app_request_setup` | The request did not reach the new app bridge or the installed binary is stale. |
| Task `97` lacks `visionOCRXXTCompat=1` | The new `streamd` is not the process currently serving port `6000`; restart it from the app. |

The debug log now records `host=foreground_app_6011`, app PID/UID, application
state, and normalized layout. For a `320`-pixel image, `app_request_setup` must
report `bpr=1280 bitmapInfo=0x2002`; otherwise the compact BGRA conversion is
not active.

For a successful Fast request, repeat it 20 times before trying Accurate. A
promotion requires bounded execution, a successful task `97` after every
request, correct text/coordinates, and no growth of hung workers.

## Safety Boundary

`xxt_compat` is a foreground canary, not the default. Do not route normal
scripts away from task `91` until it passes the device matrix. This path does
not claim background or lock-screen OCR support.
