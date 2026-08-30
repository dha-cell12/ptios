param(
    [Parameter(Mandatory = $true)][string]$HostIP,
    [int]$TaskPort = 6000,
    [int]$StreamPort = 7003,
    [ValidateRange(5, 120)][int]$SampleSeconds = 10,
    [string]$OutputRoot = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkTask([string]$Line, [int]$TimeoutMs = 10000) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = $TimeoutMs
        $client.SendTimeout = $TimeoutMs
        $client.Connect($HostIP, $TaskPort)
        $stream = $client.GetStream()
        $bytes = [Text.Encoding]::UTF8.GetBytes("$Line`r`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $reader = [IO.StreamReader]::new($stream)
        try { return $reader.ReadLine() } finally { $reader.Dispose() }
    } finally {
        $client.Dispose()
    }
}

function ConvertFrom-TLinkJson([string]$Raw) {
    if ($Raw -notlike "0;;*") { throw "TLink task failed: $Raw" }
    $encoded = ($Raw -split ";;", 2)[1]
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)) | ConvertFrom-Json
}

function Invoke-StreamControl([string]$Action, [hashtable]$Arguments = @{}) {
    $request = @{ schema = "stream_control_v2"; action = $Action }
    foreach ($key in $Arguments.Keys) { $request[$key] = $Arguments[$key] }
    $json = $request | ConvertTo-Json -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    ConvertFrom-TLinkJson (Invoke-TLinkTask "93$encoded")
}

function Get-CapturePipeline {
    $hello = ConvertFrom-TLinkJson (Invoke-TLinkTask "60")
    $pipeline = $hello.adaptive_streaming.capture_pipeline
    if (-not $pipeline -or $pipeline.schema -ne "capture_pipeline_v2") {
        throw "Task 60 does not expose capture_pipeline_v2"
    }
    return $pipeline
}

function Measure-StreamMode([string]$Mode) {
    $null = Invoke-StreamControl "set_capture_mode" @{ mode = $Mode; reset_metrics = $true }
    Start-Sleep -Milliseconds 350
    $bytesRead = 0L
    $client = [Net.Sockets.TcpClient]::new()
    $started = [DateTime]::UtcNow
    try {
        $client.ReceiveTimeout = 1000
        $client.Connect($HostIP, $StreamPort)
        $stream = $client.GetStream()
        $buffer = New-Object byte[] 65536
        $deadline = [DateTime]::UtcNow.AddSeconds($SampleSeconds)
        while ([DateTime]::UtcNow -lt $deadline) {
            try {
                $count = $stream.Read($buffer, 0, $buffer.Length)
                if ($count -le 0) { break }
                $bytesRead += $count
            } catch [IO.IOException] {
                # A receive timeout is normal between encoded frames.
            }
        }
    } finally {
        $client.Dispose()
    }
    $elapsed = ([DateTime]::UtcNow - $started).TotalSeconds
    Start-Sleep -Milliseconds 350
    $pipeline = Get-CapturePipeline
    [pscustomobject]@{
        mode = $Mode
        elapsed_seconds = [Math]::Round($elapsed, 3)
        bytes_read = $bytesRead
        frames_per_second = [Math]::Round(([double]$pipeline.capture_count / [Math]::Max($elapsed, 0.001)), 3)
        pipeline = $pipeline
    }
}

function Get-ImprovementPercent([double]$Legacy, [double]$V2) {
    if ($Legacy -le 0) { return $null }
    return [Math]::Round((($Legacy - $V2) / $Legacy) * 100.0, 2)
}

$capability = Invoke-TLinkTask "97" 5000
foreach ($marker in @("streamControlTask=93", "streamCaptureBenchmark=task93_legacy_vs_accelerated_v2")) {
    if ($capability -notlike "*$marker*") { throw "Installed build lacks '$marker'" }
}

$legacy = $null
$v2 = $null
try {
    $legacy = Measure-StreamMode "legacy"
    $v2 = Measure-StreamMode "accelerated"
} finally {
    try { $null = Invoke-StreamControl "set_capture_mode" @{ mode = "auto"; reset_metrics = $false } } catch {
        Write-Warning "Could not restore capture mode to auto: $($_.Exception.Message)"
    }
}

$legacyPipeline = $legacy.pipeline
$v2Pipeline = $v2.pipeline
$comparison = [ordered]@{
    schema = "stream_capture_comparison_v1"
    host = $HostIP
    stream_port = $StreamPort
    sample_seconds = $SampleSeconds
    legacy = $legacy
    v2 = $v2
    improvement_percent = [ordered]@{
        capture_average = Get-ImprovementPercent $legacyPipeline.capture_metrics.average_us $v2Pipeline.capture_metrics.average_us
        scale_average = Get-ImprovementPercent $legacyPipeline.scale_metrics.average_us $v2Pipeline.scale_metrics.average_us
        total_average = Get-ImprovementPercent $legacyPipeline.total_metrics.average_us $v2Pipeline.total_metrics.average_us
        total_p50 = Get-ImprovementPercent $legacyPipeline.total_metrics.p50_us $v2Pipeline.total_metrics.p50_us
        total_p95 = Get-ImprovementPercent $legacyPipeline.total_metrics.p95_us $v2Pipeline.total_metrics.p95_us
        frame_rate_gain = if ($legacy.frames_per_second -gt 0) {
            [Math]::Round((($v2.frames_per_second - $legacy.frames_per_second) / $legacy.frames_per_second) * 100.0, 2)
        } else { $null }
    }
    decision = if (
        [int64]$legacyPipeline.legacy_count -gt 0 -and
        [int64]$legacyPipeline.legacy_count -eq [int64]$legacyPipeline.capture_count -and
        [int64]$v2Pipeline.accelerated_count -gt 0 -and
        [int64]$v2Pipeline.accelerated_count -eq [int64]$v2Pipeline.capture_count -and
        [int64]$v2Pipeline.coherence_barrier_count -ge [int64]$v2Pipeline.accelerated_count -and
        [int64]$v2Pipeline.coherence_barrier_failure_count -eq 0 -and
        [int64]$v2Pipeline.source_seed_mismatch_count -eq 0 -and
        [int64]$v2Pipeline.integrity_fallback_count -eq 0 -and
        [bool]$v2Pipeline.accelerator_run_loop_attached -and
        [int64]$legacyPipeline.fallback_count -eq 0 -and
        [int64]$v2Pipeline.fallback_count -eq 0 -and
        [int64]$legacyPipeline.failure_count -eq 0 -and
        [int64]$v2Pipeline.failure_count -eq 0
    ) { "pass_comparable" } else { "fail_not_comparable" }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outputDirectory = Join-Path $OutputRoot "stream-capture-comparison-$stamp"
$null = New-Item -ItemType Directory -Path $outputDirectory -Force
$outputPath = Join-Path $outputDirectory "stream-capture-comparison.json"
$comparison | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding UTF8

[pscustomobject]@{
    decision = $comparison.decision
    legacy_fps = $legacy.frames_per_second
    v2_fps = $v2.frames_per_second
    legacy_total_average_us = $legacyPipeline.total_metrics.average_us
    v2_total_average_us = $v2Pipeline.total_metrics.average_us
    total_average_improvement_percent = $comparison.improvement_percent.total_average
    total_p95_improvement_percent = $comparison.improvement_percent.total_p95
    v2_coherence_barrier_count = $v2Pipeline.coherence_barrier_count
    v2_integrity_fallback_count = $v2Pipeline.integrity_fallback_count
    v2_accelerator_run_loop_attached = $v2Pipeline.accelerator_run_loop_attached
    output = $outputPath
} | Format-List

if ($comparison.decision -ne "pass_comparable") { exit 1 }
