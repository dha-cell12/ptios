param(
    [Parameter(Mandatory = $true)][string]$HostIP,
    [Parameter(Mandatory = $true)][ValidateSet("rootfull", "trollstore")][string]$Runtime,
    [int]$Port = 6000,
    [switch]$RunScriptSmoke,
    [string]$ScriptPath = ""
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkEventTask {
    param([Parameter(Mandatory = $true)][string]$Task, [int]$ReceiveTimeout = 35000)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = $ReceiveTimeout
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $request = [Text.Encoding]::UTF8.GetBytes("$Task`r`n")
        $stream.Write($request, 0, $request.Length)
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $false, 8192, $true)
        try { return $reader.ReadLine() } finally { $reader.Dispose() }
    } finally { $client.Dispose() }
}

function Send-TLinkEventTask {
    param([Parameter(Mandatory = $true)][string]$Task)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $request = [Text.Encoding]::UTF8.GetBytes("$Task`r`n")
        $stream.Write($request, 0, $request.Length)
        $stream.Flush()
    } finally { $client.Dispose() }
}

function ConvertFrom-TLinkEventResponse {
    param([string]$Raw)
    if ($Raw -notlike "0;;*") { throw "Event task failed: $Raw" }
    $b64 = ($Raw -split ";;", 2)[1]
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
}

$capability = Invoke-TLinkEventTask -Task "97" -ReceiveTimeout 5000
$required = @(
    "runtime=$Runtime", "eventChannelState=implemented", "eventChannelVersion=1",
    "eventChannelSchema=event_channel_v1", "eventChannelTransport=task95_long_poll_v1",
    "eventChannelResume=cursor_v1", "eventChannelJournalMaxEvents=256",
    "eventChannelPollMaxEvents=32", "eventChannelPollTimeoutMaxMs=25000",
    "eventChannelDeviceValidated=0"
)
foreach ($marker in $required) {
    if ($capability -notlike "*$marker*") { throw "Task 97 missing '$marker'" }
}

$initial = ConvertFrom-TLinkEventResponse (Invoke-TLinkEventTask -Task "950;;0;;1;;script.run" -ReceiveTimeout 5000)
if ($initial.schema -ne "event_channel_v1") { throw "event channel schema mismatch" }
$cursor = [uint64]$initial.latest_cursor

$received = $null
if ($RunScriptSmoke) {
    if (-not $ScriptPath) {
        $ScriptPath = if ($Runtime -eq "rootfull") {
            "/var/mobile/Library/TLinkauto/scripts/examples/Failure Evidence Smoke.tl"
        } else {
            "/var/mobile/Library/TLinkauto/scripts/Compatibility Tests/10 Failure Evidence.tl"
        }
    }
    $pollJob = Start-Job -ScriptBlock {
        param($IP, $PortValue, $CursorValue)
        $client = [Net.Sockets.TcpClient]::new()
        try {
            $client.ReceiveTimeout = 35000
            $client.Connect($IP, $PortValue)
            $stream = $client.GetStream()
            $bytes = [Text.Encoding]::UTF8.GetBytes("95$CursorValue;;25000;;8;;script.run`r`n")
            $stream.Write($bytes, 0, $bytes.Length)
            $reader = [IO.StreamReader]::new($stream)
            try { $reader.ReadLine() } finally { $reader.Dispose() }
        } finally { $client.Dispose() }
    } -ArgumentList $HostIP, $Port, $cursor
    try {
        Start-Sleep -Milliseconds 300
        # Task 19 is deliberately fire-and-forget on rootfull.
        Send-TLinkEventTask -Task "19$ScriptPath"
        $raw = Receive-Job -Job $pollJob -Wait -AutoRemoveJob
        $received = ConvertFrom-TLinkEventResponse $raw
        if (@($received.events).Count -eq 0) { throw "long poll returned no script.run event" }
        if ($received.events[0].topic -ne "script.run") { throw "unexpected topic" }
        if ([uint64]$received.next_cursor -le $cursor) { throw "cursor did not advance" }
    } finally {
        if ($pollJob.State -notin @("Completed", "Failed", "Stopped")) { Stop-Job $pollJob }
        Remove-Job $pollJob -Force -ErrorAction SilentlyContinue
    }
}

[pscustomobject]@{
    host = $HostIP
    runtime = $Runtime
    schema = $initial.schema
    latest_cursor = $initial.latest_cursor
    script_smoke_run = [bool]$RunScriptSmoke
    received_events = if ($received) { @($received.events).Count } else { 0 }
    gap = if ($received) { [bool]$received.gap } else { $false }
    device_validated = $false
} | Format-List
