[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [ValidateRange(20, 100)]
    [int]$FastRepeatCount = 20,
    [ValidateRange(1000, 120000)]
    [int]$TimeoutMs = 30000,
    [ValidateRange(0, 5000)]
    [int]$InterRunDelayMs = 100,
    [int]$RegionX = 0,
    [int]$RegionY = 0,
    [ValidateRange(1, 4096)]
    [int]$FastWidth = 320,
    [ValidateRange(1, 4096)]
    [int]$FastHeight = 160,
    [ValidateRange(1, 4096)]
    [int]$LargeWidth = 640,
    [ValidateRange(1, 4096)]
    [int]$LargeHeight = 320,
    [string]$VisionLanguages = "en-US",
    [string]$ExpectedText = "",
    [string]$Notes = "",
    [switch]$FailOnGate,
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"
$qualificationVersion = "foreground_fast20_accurate1_largefast1_v2"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputDirectory = Join-Path (Get-Location) "ocr-qualification-$stamp"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null

function Invoke-TLinkTask {
    param([Parameter(Mandatory = $true)][string]$Task)

    $started = [DateTimeOffset]::UtcNow
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $client = [System.Net.Sockets.TcpClient]::new()
    $client.ReceiveTimeout = $TimeoutMs
    $client.SendTimeout = $TimeoutMs
    $stream = $null
    $writer = $null
    $reader = $null
    try {
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $encoding = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($stream, $encoding, 1024, $true)
        $writer.NewLine = "`r`n"
        $writer.AutoFlush = $true
        $reader = [System.IO.StreamReader]::new($stream, $encoding, $false, 4096, $true)
        $writer.WriteLine($Task)
        $response = $reader.ReadLine()
        if ($null -eq $response) {
            throw "Port $Port closed without a response."
        }
        $timer.Stop()
        return [ordered]@{
            at_utc = $started.ToString("o")
            request = $Task
            response = $response
            ok = $response -eq "0" -or $response.StartsWith("0;;", [StringComparison]::Ordinal)
            roundtrip_ms = [Math]::Round($timer.Elapsed.TotalMilliseconds, 3)
            error = $null
        }
    }
    catch {
        $timer.Stop()
        return [ordered]@{
            at_utc = $started.ToString("o")
            request = $Task
            response = $null
            ok = $false
            roundtrip_ms = [Math]::Round($timer.Elapsed.TotalMilliseconds, 3)
            error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $writer) { $writer.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        $client.Dispose()
    }
}

function Add-TLinkVisionDebugText {
    param([object]$Probe)
    if (-not $Probe.ok -or [string]::IsNullOrWhiteSpace([string]$Probe.response)) {
        return
    }
    $parts = @(([string]$Probe.response).Split(@(";;"), [StringSplitOptions]::None))
    if ($parts.Count -lt 3 -or $parts[1] -ne "vision_debug_base64") {
        return
    }
    try {
        $Probe["decoded_log"] = if ([string]::IsNullOrEmpty($parts[2])) {
            ""
        } else {
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[2]))
        }
    }
    catch {
        $Probe["decode_error"] = $_.Exception.Message
    }
}

function New-TLinkVisionTask {
    param(
        [Parameter(Mandatory = $true)][int]$RecognitionLevel,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )
    $rect = "$RegionX,,$RegionY,,$Width,,$Height"
    return "271;;$rect;;;;0.03125;;$RecognitionLevel;;$VisionLanguages;;0;;;;xxt_compat"
}

function Invoke-TLinkVisionCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$RecognitionLevel,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height,
        [int]$Iteration = 1
    )
    $vision = Invoke-TLinkTask -Task (New-TLinkVisionTask -RecognitionLevel $RecognitionLevel -Width $Width -Height $Height)
    $postflight = Invoke-TLinkTask -Task "97"
    $textMatched = $true
    if (-not [string]::IsNullOrWhiteSpace($ExpectedText)) {
        $textMatched = $vision.ok -and ([string]$vision.response).IndexOf($ExpectedText, [StringComparison]::OrdinalIgnoreCase) -ge 0
    }
    $missingPostflightMarkers = @()
    foreach ($marker in $requiredTask97Markers) {
        if (-not $postflight.ok -or ([string]$postflight.response).IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
            $missingPostflightMarkers += $marker
        }
    }
    return [ordered]@{
        name = $Name
        iteration = $Iteration
        recognition_level = $RecognitionLevel
        region = [ordered]@{ x = $RegionX; y = $RegionY; width = $Width; height = $Height }
        vision = $vision
        task97_postflight = $postflight
        missing_postflight_markers = $missingPostflightMarkers
        expected_text_matched = $textMatched
        passed = [bool]($vision.ok -and $postflight.ok -and $missingPostflightMarkers.Count -eq 0 -and $textMatched)
    }
}

function Get-TLinkMetricSummary {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) {
        return $null
    }
    $sorted = @($Values | Sort-Object)
    $p50Index = [Math]::Max(0, [Math]::Ceiling($sorted.Count * 0.50) - 1)
    $p95Index = [Math]::Max(0, [Math]::Ceiling($sorted.Count * 0.95) - 1)
    return [ordered]@{
        count = $sorted.Count
        min_ms = [Math]::Round($sorted[0], 3)
        p50_ms = [Math]::Round($sorted[$p50Index], 3)
        p95_ms = [Math]::Round($sorted[$p95Index], 3)
        max_ms = [Math]::Round($sorted[-1], 3)
    }
}

$requiredTask97Markers = @(
    "visionOCRState=experimental",
    "visionOCRXXTCompat=1",
    "visionOCRXXTCompatHost=foreground_app_6011",
    "visionOCRXXTCompatForegroundRequired=1",
    "visionOCRPixelBufferProbe=bgra_420f_memory_iosurface_opengles_metal_v1",
    "visionOCRGraphicsEntitlements=iosurface_ioaccel_agx_v1",
    "visionOCRAppBridgeProbe=task275_v1",
    "visionOCRQualification=$qualificationVersion"
)

$capturedAt = [DateTimeOffset]::UtcNow
$preflight = Invoke-TLinkTask -Task "97"
$missingMarkers = @()
foreach ($marker in $requiredTask97Markers) {
    if (-not $preflight.ok -or ([string]$preflight.response).IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        $missingMarkers += $marker
    }
}
$preflightReady = [bool]($preflight.ok -and $missingMarkers.Count -eq 0)
$appBridgePreflight = Invoke-TLinkTask -Task "275"
$appBridgeReady = [bool](
    $appBridgePreflight.ok -and
    ([string]$appBridgePreflight.response).IndexOf("app_ocr_ready", [StringComparison]::Ordinal) -ge 0 -and
    ([string]$appBridgePreflight.response).IndexOf("state=0", [StringComparison]::Ordinal) -ge 0
)
$debugClear = Invoke-TLinkTask -Task "274"

$fastRuns = [System.Collections.Generic.List[object]]::new()
$stoppedEarly = -not $preflightReady -or -not $appBridgeReady -or -not $debugClear.ok
$stopReason = if (-not $preflightReady) {
    "preflight_capability_mismatch"
} elseif (-not $appBridgeReady) {
    "app_bridge_preflight_failed"
} elseif (-not $debugClear.ok) {
    "debug_clear_failed"
} else {
    $null
}

if (-not $stoppedEarly) {
    for ($iteration = 1; $iteration -le $FastRepeatCount; $iteration++) {
        $run = Invoke-TLinkVisionCase -Name "fast_repeat" -RecognitionLevel 1 -Width $FastWidth -Height $FastHeight -Iteration $iteration
        $fastRuns.Add($run)
        if (-not $run.passed) {
            $stoppedEarly = $true
            $stopReason = "fast_iteration_$iteration`_failed"
            break
        }
        if ($InterRunDelayMs -gt 0 -and $iteration -lt $FastRepeatCount) {
            Start-Sleep -Milliseconds $InterRunDelayMs
        }
    }
}

$accurateCase = [ordered]@{ skipped = $true; reason = "fast_gate_not_complete" }
if (-not $stoppedEarly -and $fastRuns.Count -eq $FastRepeatCount) {
    $accurateCase = Invoke-TLinkVisionCase -Name "accurate_small" -RecognitionLevel 0 -Width $FastWidth -Height $FastHeight
    if (-not $accurateCase.passed) {
        $stoppedEarly = $true
        $stopReason = "accurate_small_failed"
    }
}

$largeFastCase = [ordered]@{ skipped = $true; reason = "accurate_gate_not_complete" }
if (-not $stoppedEarly -and $accurateCase.passed) {
    $largeFastCase = Invoke-TLinkVisionCase -Name "fast_large" -RecognitionLevel 1 -Width $LargeWidth -Height $LargeHeight
    if (-not $largeFastCase.passed) {
        $stoppedEarly = $true
        $stopReason = "fast_large_failed"
    }
}

$debugAfter = Invoke-TLinkTask -Task "273"
Add-TLinkVisionDebugText -Probe $debugAfter
$debugText = if ($debugAfter.Contains("decoded_log")) { [string]$debugAfter.decoded_log } else { "" }
$executedVisionCount = $fastRuns.Count
if (-not $accurateCase.skipped) { $executedVisionCount++ }
if (-not $largeFastCase.skipped) { $executedVisionCount++ }

$pixelProbeCount = [regex]::Matches($debugText, "app_pixelbuffer_probe").Count
$zeroPixelProbeCount = [regex]::Matches(
    $debugText,
    "app_pixelbuffer_probe[^\r\n]*bgra_memory=0 420f_memory=0 420f_iosurface=0 420f_opengles=0 420f_metal=0"
).Count
$performEndCount = [regex]::Matches($debugText, "app_perform_end").Count
$responseReadyCount = [regex]::Matches($debugText, "app_response_ready").Count
$allPixelBuffersZero = $pixelProbeCount -ge $executedVisionCount -and $zeroPixelProbeCount -ge $executedVisionCount
$debugHasFailure = $debugText -match "app_perform_failed|app_ocr_requires_foreground|app_ocr_timeout|app_ocr_busy|app_image_decode_failed"
$debugHealthy = [bool](
    $debugAfter.ok -and
    $executedVisionCount -gt 0 -and
    $allPixelBuffersZero -and
    $performEndCount -ge $executedVisionCount -and
    $responseReadyCount -ge $executedVisionCount -and
    -not $debugHasFailure
)

$fastPassed = $fastRuns.Count -eq $FastRepeatCount -and @($fastRuns | Where-Object { -not $_.passed }).Count -eq 0
$automatedGatePassed = [bool](
    $preflightReady -and $appBridgeReady -and
    $debugClear.ok -and
    $fastPassed -and
    -not $accurateCase.skipped -and $accurateCase.passed -and
    -not $largeFastCase.skipped -and $largeFastCase.passed -and
    $debugHealthy
)

$roundtrips = @($fastRuns | ForEach-Object { [double]$_.vision.roundtrip_ms })
if (-not $accurateCase.skipped) { $roundtrips += [double]$accurateCase.vision.roundtrip_ms }
if (-not $largeFastCase.skipped) { $roundtrips += [double]$largeFastCase.vision.roundtrip_ms }

$decision = if ($automatedGatePassed) {
    "pass_automated_gate_manual_text_coordinate_review_required"
} elseif ($stoppedEarly) {
    "fail_stopped_early"
} else {
    "fail_debug_or_completion_gate"
}

$artifact = [ordered]@{
    metadata = [ordered]@{
        schema_version = 1
        qualification_version = $qualificationVersion
        captured_at_utc = $capturedAt.ToString("o")
        completed_at_utc = [DateTimeOffset]::UtcNow.ToString("o")
        host = $HostIP
        port = $Port
        timeout_ms = $TimeoutMs
        inter_run_delay_ms = $InterRunDelayMs
        notes = $Notes
        expected_text = $ExpectedText
        foreground_app_required = $true
        profile = "xxt_compat"
    }
    preflight = [ordered]@{
        task97 = $preflight
        required_markers = $requiredTask97Markers
        missing_markers = $missingMarkers
        app_bridge = $appBridgePreflight
        app_bridge_ready = $appBridgeReady
        passed = [bool]($preflightReady -and $appBridgeReady)
    }
    debug_clear = $debugClear
    fast_runs = @($fastRuns)
    accurate_case = $accurateCase
    large_fast_case = $largeFastCase
    debug_after = $debugAfter
    summary = [ordered]@{
        decision = $decision
        automated_gate_passed = $automatedGatePassed
        promotion_ready = $false
        promotion_blocker = "manual text and coordinate review plus background fail-closed check"
        stopped_early = $stoppedEarly
        stop_reason = $stopReason
        requested_fast_runs = $FastRepeatCount
        completed_fast_runs = $fastRuns.Count
        executed_vision_requests = $executedVisionCount
        roundtrip = Get-TLinkMetricSummary -Values $roundtrips
        debug = [ordered]@{
            healthy = $debugHealthy
            pixel_probe_count = $pixelProbeCount
            zero_pixel_probe_count = $zeroPixelProbeCount
            perform_end_count = $performEndCount
            response_ready_count = $responseReadyCount
            all_pixel_buffers_zero = $allPixelBuffersZero
            failure_marker_found = $debugHasFailure
        }
    }
}

$jsonPath = Join-Path $resolvedOutput "ocr-qualification.json"
$artifact | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

Write-Host "Vision OCR qualification written to $jsonPath"
Write-Host "Decision: $decision"
if ($automatedGatePassed) {
    Write-Host "Automated stability gate passed. Review recognized text/coordinates and verify background fail-closed behavior before promotion."
} else {
    Write-Warning "Vision OCR qualification did not pass. Inspect summary, the failed case, and debug_after.decoded_log."
}
if ($FailOnGate -and -not $automatedGatePassed) {
    exit 1
}
