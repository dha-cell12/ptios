param(
    [Parameter(Mandatory = $true)][string]$HostIP,
    [Parameter(Mandatory = $true)][ValidateSet("rootfull", "trollstore")][string]$Runtime,
    [int]$Port = 6000,
    [int]$StreamPort = 7004,
    [switch]$RunFeedbackSmoke
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkAdaptiveTask([string]$Task, [int]$Timeout = 10000) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = $Timeout
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $bytes = [Text.Encoding]::UTF8.GetBytes("$Task`r`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $reader = [IO.StreamReader]::new($stream)
        try { return $reader.ReadLine() } finally { $reader.Dispose() }
    } finally { $client.Dispose() }
}

function ConvertFrom-TLinkBase64Json([string]$Raw) {
    if ($Raw -notlike "0;;*") { throw "TLink task failed: $Raw" }
    $b64 = ($Raw -split ";;", 2)[1]
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
}

$capability = Invoke-TLinkAdaptiveTask "97" 5000
foreach ($marker in @(
    "runtime=$Runtime", "adaptiveStreamingState=implemented", "adaptiveStreamingVersion=1",
    "adaptiveStreamingSchema=adaptive_streaming_v1", "adaptiveStreamingFeedback=task94_base64_json_v1",
    "adaptiveStreamingLevels=high,balanced,survival",
    "adaptiveStreamingSelfHealing=encoder_restart_3_client_reconnect_6",
    "adaptiveStreamingDeviceValidated=0"
)) {
    if ($capability -notlike "*$marker*") { throw "Task 97 missing '$marker'" }
}

$accepted = $null
if ($RunFeedbackSmoke) {
    $feedback = [ordered]@{
        schema = "stream_feedback_v1"; port = $StreamPort; fps = 4; kbps = 250
        decode_queue = 10; dropped = 8; total_approx_ms = 450; stalled = $true
    } | ConvertTo-Json -Compress
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($feedback))
    $accepted = ConvertFrom-TLinkBase64Json (Invoke-TLinkAdaptiveTask "94$b64")
    if ($accepted.state -ne "accepted") { throw "Feedback was not accepted" }
}

$hello = ConvertFrom-TLinkBase64Json (Invoke-TLinkAdaptiveTask "60")
if ($hello.adaptive_streaming.schema -ne "adaptive_streaming_v1") {
    throw "Task 60 adaptive_streaming schema mismatch"
}

[pscustomobject]@{
    host = $HostIP
    runtime = $Runtime
    schema = $hello.adaptive_streaming.schema
    policy = $hello.adaptive_streaming.policy
    session_count = @($hello.adaptive_streaming.sessions).Count
    feedback_smoke_run = [bool]$RunFeedbackSmoke
    feedback_state = if ($accepted) { $accepted.state } else { "not_run" }
    device_validated = $false
} | Format-List
