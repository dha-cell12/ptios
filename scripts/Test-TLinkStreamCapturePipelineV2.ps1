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

$capability = Invoke-TLinkCaptureTask "97" 5000
foreach ($marker in @(
    "streamCapturePipeline=iosurface_pool_gpu_scale_v2",
    "streamCapturePreferredBackend=iosurface_accelerator",
    "streamCaptureFallback=coregraphics_v1",
    "streamCaptureSourcePool=2",
    "streamCaptureTarget=encoder_iosurface_pixel_buffer",
    "streamCaptureDiagnostics=task60_adaptive_streaming_capture_pipeline",
    "streamCaptureDeviceValidated=1"
)) {
    if ($capability -notlike "*$marker*") { throw "Task 97 missing '$marker'" }
}

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

$decision = if ([int64]$pipeline.accelerated_count -gt 0) {
    "pass_accelerated"
} elseif ([int64]$pipeline.fallback_count -gt 0 -and [int64]$pipeline.failure_count -eq 0) {
    "pass_coregraphics_fallback"
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
    source_size = "$($pipeline.source_width)x$($pipeline.source_height)"
    last_capture_us = $pipeline.last_capture_us
    last_scale_us = $pipeline.last_scale_us
    last_total_us = $pipeline.last_total_us
    last_transfer_result = $pipeline.last_transfer_result
    last_result = $pipeline.last_result
} | Format-List

if ($decision -eq "fail_capture_pipeline") { exit 1 }
