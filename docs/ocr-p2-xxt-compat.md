# OCR P2 XXTouch-Compatible Vision Canary

## Scope

P2 adds the opt-in task `27` profile `xxt_compat`. It intentionally mirrors
the Apple OCR path recovered from XXTouch's `libxxtouch.so`:

- construct `VNRecognizeTextRequest` with plain `init`;
- pass the cropped `CGImage` directly to `VNImageRequestHandler`;
- call `performRequests:error:` synchronously;
- leave compute-device selection to Vision (no `usesCPUOnly`);
- default to `en-US` when no language was supplied.

The existing `app_cpu` default, opt-in `worker_cpu`, task `27` response bytes,
and production task `91` Tesseract path are unchanged. `xxt_compat` still runs
inside the isolated OCR worker so a Vision crash cannot terminate the main
task server on port `6000`.

## First Device Test

Use a small region and Fast recognition for the first request after installing
the build:

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

## Interpreting Results

| Last phase or response | Meaning |
|---|---|
| `response_ready` and `0;;...` | Vision completed and task `27` produced a valid legacy response. |
| `perform_failed` | Vision returned an `NSError`; retain its domain, code, and text. |
| `perform_begin` plus `ocr_worker_crashed signal=11 phase=vision_xxt_compat_perform_requests` | Vision crashed inside `performRequests`; the main server should remain alive. |
| `perform_begin` plus `ocr_worker_timeout timeout_ms=20000` | Vision blocked; increasing the client timeout is not a fix. |
| No `request_setup` | Failure occurred during capture/crop or the installed binary is stale. |
| Task `97` lacks `visionOCRXXTCompat=1` | The new `streamd` is not the process currently serving port `6000`; restart it from the app. |

For a successful Fast request, repeat it 20 times before trying Accurate. A
promotion requires bounded execution, a successful task `97` after every
request, correct text/coordinates, and no growth of hung workers.

## Safety Boundary

`xxt_compat` is a canary, not the default. Do not route normal scripts away
from task `91` until it passes the device matrix. Do not add extra private
entitlements based only on a Vision crash: class loading and request setup
already prove that the framework is available.
