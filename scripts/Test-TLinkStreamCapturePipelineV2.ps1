param(
    [Parameter(Mandatory = $true)][string]$HostIP,
    [int]$TaskPort = 6000,
    [int]$StreamPort = 7003,
    [ValidateRange(1, 60)][int]$DrainSeconds = 5
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkCaptureTask([string]$Task, [int]$Timeout = 10000) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = $Timeout
        $client.Connect($HostIP, $TaskPort)
        $stream = $client.GetStream()
        $bytes = [Text.Encoding]::UTF8.GetBytes("$Task`r`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $reader = [IO.StreamReader]::new($stream)
        try { return $reader.ReadLine() } finally { $reader.Dispose() }
    } finally { $client.Dispose() }
}

function ConvertFrom-TLinkCaptureJson([string]$Raw) {
    if ($Raw -notlike "0;;*") { throw "TLink task failed: $Raw" }
    $base64 = ($Raw -split ";;", 2)[1]
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64)) | ConvertFrom-Json
}

function Invoke-TLinkStreamControl([string]$Action, [hashtable]$Arguments = @{}) {
    $request = @{ schema = "stream_control_v2"; action = $Action }
    foreach ($key in $Arguments.Keys) { $request[$key] = $Arguments[$key] }
    $json = $request | ConvertTo-Json -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    ConvertFrom-TLinkCaptureJson (Invoke-TLinkCaptureTask "93$encoded")
}

$capability = Invoke-TLinkCaptureTask "97" 5000
foreach ($marker in @(
    "streamCapturePipeline=iosurface_pool_gpu_scale_v2",
    "streamCapturePreferredBackend=coregraphics_fresh_surface_safe",
    "streamCaptureAcceleratorPolicy=unsafe_opt_in_only",
    "streamCaptureFallback=coregraphics_v1",
    "streamCaptureSourcePool=2",
    "streamCaptureStagingCache=4",
    "streamCaptureTarget=encoder_iosurface_pixel_buffer",
    "streamCaptureAcceleratorTarget=explicit_bgra_staging_surface",
    "streamCaptureDiagnostics=task60_adaptive_streaming_capture_pipeline",
    "streamCaptureSynchronization=fresh_iosurface_cgimage_draw_v5",
    "streamCaptureIntegrityDeviceValidated=0",
    "streamCaptureDeviceValidated=1"
)) {
    if ($capability -notlike "*$marker*") { throw "Task 97 missing '$marker'" }
}

# Qualification must not inherit a previous diagnostic `legacy` selection or
# stale counters. The installed runtime remains in auto after the test.
$null = Invoke-TLinkStreamControl "set_capture_mode" @{ mode = "auto"; reset_metrics = $true }
Start-Sleep -Milliseconds 250

$bytesRead = 0L
$streamClient = [Net.Sockets.TcpClient]::new()
try {
    $streamClient.ReceiveTimeout = 1000
    $streamClient.Connect($HostIP, $StreamPort)
    $networkStream = $streamClient.GetStream()
    $buffer = New-Object byte[] 65536
    $deadline = [DateTime]::UtcNow.AddSeconds($DrainSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $read = $networkStream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $bytesRead += $read
        } catch [IO.IOException] {
            # A one-second receive timeout is expected while waiting for the
            # next encoded frame; keep draining until the qualification window.
        }
    }
} finally {
    $streamClient.Dispose()
}

Start-Sleep -Milliseconds 250
$hello = ConvertFrom-TLinkCaptureJson (Invoke-TLinkCaptureTask "60")
$pipeline = $hello.adaptive_streaming.capture_pipeline
if (-not $pipeline) { throw "Task 60 missing adaptive_streaming.capture_pipeline" }
if ($pipeline.schema -ne "capture_pipeline_v2") {
    throw "Unexpected capture pipeline schema '$($pipeline.schema)'"
}
if ([int64]$pipeline.capture_count -le 0) { throw "Capture pipeline did not produce a frame" }
if ($bytesRead -le 0) { throw "Stream port $StreamPort returned no encoded bytes" }

$decision = if (
    [int64]$pipeline.safe_copy_count -gt 0 -and
    [int64]$pipeline.safe_copy_count -eq [int64]$pipeline.capture_count -and
    [int64]$pipeline.safe_copy_failure_count -eq 0 -and
    [int64]$pipeline.fallback_count -eq 0 -and
    [int64]$pipeline.failure_count -eq 0 -and
    $pipeline.active_backend -eq "coregraphics_fresh_surface_safe"
) {
    "pass_fresh_surface_safe"
} elseif ([int64]$pipeline.fallback_count -gt 0 -and [int64]$pipeline.failure_count -eq 0) {
    "pass_safe_coregraphics_fallback"
} else {
    "fail_capture_pipeline"
}

[pscustomobject]@{
    host = $HostIP
    stream_port = $StreamPort
    drain_seconds = $DrainSeconds
    bytes_read = $bytesRead
    decision = $decision
    active_backend = $pipeline.active_backend
    capture_count = $pipeline.capture_count
    accelerated_count = $pipeline.accelerated_count
    fallback_count = $pipeline.fallback_count
    failure_count = $pipeline.failure_count
    coherence_barrier_count = $pipeline.coherence_barrier_count
    coherence_barrier_failure_count = $pipeline.coherence_barrier_failure_count
    source_seed_mismatch_count = $pipeline.source_seed_mismatch_count
    destination_seed_unchanged_count = $pipeline.destination_seed_unchanged_count
    integrity_fallback_count = $pipeline.integrity_fallback_count
    staged_copy_count = $pipeline.staged_copy_count
    staging_allocation_count = $pipeline.staging_allocation_count
    staging_copy_failure_count = $pipeline.staging_copy_failure_count
    safe_copy_count = $pipeline.safe_copy_count
    safe_copy_failure_count = $pipeline.safe_copy_failure_count
    direct_encoder_surface_transfer = $pipeline.direct_encoder_surface_transfer
    accelerator_run_loop_attached = $pipeline.accelerator_run_loop_attached
    source_size = "$($pipeline.source_width)x$($pipeline.source_height)"
    last_capture_us = $pipeline.last_capture_us
    last_scale_us = $pipeline.last_scale_us
    last_total_us = $pipeline.last_total_us
    last_transfer_result = $pipeline.last_transfer_result
    last_coherence_barrier_result = $pipeline.last_coherence_barrier_result
    last_staging_size = "$($pipeline.last_staging_width)x$($pipeline.last_staging_height)"
    last_staging_bytes_per_row = $pipeline.last_staging_bytes_per_row
    last_target_bytes_per_row = $pipeline.last_target_bytes_per_row
    last_result = $pipeline.last_result
} | Format-List

if ($decision -eq "fail_capture_pipeline") { exit 1 }
