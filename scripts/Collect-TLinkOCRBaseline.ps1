[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [int]$TimeoutMs = 20000,
    [int]$RegionX = 0,
    [int]$RegionY = 0,
    [int]$RegionWidth = 640,
    [int]$RegionHeight = 320,
    [ValidateSet(0, 1)]
    [int]$RecognitionLevel = 0,
    [string]$VisionLanguages = "en-US",
    [string]$TesseractLanguage = "eng",
    [ValidateSet("foreground", "background", "locked", "after_respring", "after_reboot", "unknown")]
    [string]$Context = "unknown",
    [string]$DeviceModel = "",
    [string]$SoC = "",
    [string]$IOSVersion = "",
    [string]$BuildIdentifier = "",
    [string]$Notes = "",
    [string]$DeviceLogPath = "",
    [switch]$RunVision,
    [ValidateSet("app_cpu", "worker_cpu", "xxt_compat")]
    [string]$VisionProfile = "app_cpu",
    [switch]$ClearVisionDebugLog,
    [switch]$SkipTesseract,
    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

if ($RegionWidth -le 0 -or $RegionHeight -le 0) {
    throw "RegionWidth and RegionHeight must be positive."
}
if ($TimeoutMs -lt 1000) {
    throw "TimeoutMs must be at least 1000."
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputDirectory = Join-Path (Get-Location) "ocr-baseline-$stamp"
}
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
[System.IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null

function Invoke-TLinkTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Task
    )

    $started = [DateTimeOffset]::UtcNow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
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
        $stopwatch.Stop()
        return [ordered]@{
            at_utc = $started.ToString("o")
            request = $Task
            response = $response
            ok = $response -eq "0" -or $response.StartsWith("0;;", [StringComparison]::Ordinal)
            roundtrip_ms = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
            error = $null
        }
    }
    catch {
        $stopwatch.Stop()
        return [ordered]@{
            at_utc = $started.ToString("o")
            request = $Task
            response = $null
            ok = $false
            roundtrip_ms = [Math]::Round($stopwatch.Elapsed.TotalMilliseconds, 3)
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

function Get-TLinkSuccessParts {
    param([object]$Probe)
    if (-not $Probe.ok -or [string]::IsNullOrWhiteSpace([string]$Probe.response)) {
        return @()
    }
    return @(([string]$Probe.response).Split(@(";;"), [StringSplitOptions]::None) | Select-Object -Skip 1)
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

$metadata = [ordered]@{
    schema_version = 1
    captured_at_utc = [DateTimeOffset]::UtcNow.ToString("o")
    host = $HostIP
    port = $Port
    timeout_ms = $TimeoutMs
    context = $Context
    device_model = $DeviceModel
    soc = $SoC
    ios_version = $IOSVersion
    build_identifier = $BuildIdentifier
    notes = $Notes
    region = [ordered]@{
        x = $RegionX
        y = $RegionY
        width = $RegionWidth
        height = $RegionHeight
    }
    vision_opt_in = [bool]$RunVision
    vision_profile = $VisionProfile
    tesseract_enabled = -not [bool]$SkipTesseract
}

$probes = [ordered]@{}
$probes.task97 = Invoke-TLinkTask -Task "97"
$probes.task60 = Invoke-TLinkTask -Task "60"
$probes.task91_languages = Invoke-TLinkTask -Task "91check_langs"

$frameId = 0
if (-not $SkipTesseract) {
    $probes.task66_capture = Invoke-TLinkTask -Task "661;;0;;3000"
    $captureParts = @(Get-TLinkSuccessParts -Probe $probes.task66_capture)
    if ($captureParts.Count -gt 0) {
        [void][int]::TryParse($captureParts[0], [ref]$frameId)
    }

    if ($frameId -gt 0) {
        try {
            $tesseractTask = "91$frameId;;$RegionX;;$RegionY;;$RegionWidth;;$RegionHeight;;$TesseractLanguage;;1;;6;;;;2;;0;;pixel;;3000"
            $probes.task91_ocr = Invoke-TLinkTask -Task $tesseractTask
        }
        finally {
            $probes.task67_release = Invoke-TLinkTask -Task "67$frameId"
        }
    }
    else {
        $probes.task91_ocr = [ordered]@{
            ok = $false
            error = "task66 did not return a positive frame id"
        }
    }
}

if ($RunVision) {
    if ($ClearVisionDebugLog) {
        $probes.task27_debug_clear = Invoke-TLinkTask -Task "274"
    }
    $probes.task27_debug_before = Invoke-TLinkTask -Task "273"
    Add-TLinkVisionDebugText -Probe $probes.task27_debug_before
    $rect = "$RegionX,,$RegionY,,$RegionWidth,,$RegionHeight"
    $visionTask = "271;;$rect;;;;0.03125;;$RecognitionLevel;;$VisionLanguages;;0;;;;$VisionProfile"
    $probes.task27_vision = Invoke-TLinkTask -Task $visionTask
    $probes.task27_debug_after = Invoke-TLinkTask -Task "273"
    Add-TLinkVisionDebugText -Probe $probes.task27_debug_after
}
else {
    $probes.task27_vision = [ordered]@{
        skipped = $true
        reason = "Vision is experimental. Re-run with -RunVision on a disposable/test device."
    }
}
$probes.task97_postflight = Invoke-TLinkTask -Task "97"

$artifact = [ordered]@{
    metadata = $metadata
    probes = $probes
}

$jsonPath = Join-Path $resolvedOutput "ocr-baseline.json"
$artifact | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$copiedLog = $null
if (-not [string]::IsNullOrWhiteSpace($DeviceLogPath)) {
    $resolvedLog = [System.IO.Path]::GetFullPath($DeviceLogPath)
    if (-not [System.IO.File]::Exists($resolvedLog)) {
        throw "DeviceLogPath does not exist: $resolvedLog"
    }
    $copiedLog = Join-Path $resolvedOutput ([System.IO.Path]::GetFileName($resolvedLog))
    Copy-Item -LiteralPath $resolvedLog -Destination $copiedLog -Force
}

Write-Host "OCR baseline written to $jsonPath"
if ($null -ne $copiedLog) {
    Write-Host "Device log copied to $copiedLog"
}
if (-not $RunVision) {
    Write-Host "Vision probe was skipped. Use -RunVision -VisionProfile xxt_compat on a test device to exercise the XXTouch-compatible canary."
}
