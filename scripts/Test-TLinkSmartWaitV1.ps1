param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [Parameter(Mandatory = $true)]
    [ValidateSet("rootfull", "trollstore")]
    [string]$Runtime,
    [int]$Port = 6000,
    [switch]$RunSmoke,
    [string]$ScriptPath = ""
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkSmartWaitTask {
    param([Parameter(Mandatory = $true)][string]$Task)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = 15000
        $client.SendTimeout = 5000
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $request = [Text.Encoding]::UTF8.GetBytes("$Task`r`n")
        $stream.Write($request, 0, $request.Length)
        $buffer = New-Object byte[] 8192
        $response = [IO.MemoryStream]::new()
        try {
            while ($response.Length -lt 262144) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $response.Write($buffer, 0, $read)
                if ([Array]::IndexOf($buffer, [byte]10, 0, $read) -ge 0) { break }
            }
            return [Text.Encoding]::UTF8.GetString($response.ToArray()).Trim()
        }
        finally { $response.Dispose() }
    }
    finally { $client.Dispose() }
}

function Get-TLinkSmartWaitStatus {
    $raw = Invoke-TLinkSmartWaitTask -Task "60"
    if ($raw -notlike "0;;*") { throw "Task 60 failed: $raw" }
    $base64 = ($raw -split ";;", 2)[1]
    return [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($base64)
    ) | ConvertFrom-Json
}

$capability = Invoke-TLinkSmartWaitTask -Task "97"
if ($capability -notlike "0;;*") { throw "Task 97 failed: $capability" }
$required = @(
    "runtime=$Runtime",
    "smartWaitState=implemented",
    "smartWaitPhase=1",
    "smartWaitSchema=smart_wait_result_v1",
    "smartWaitClients=rootfull_js_trollstore_js_webtango_v1",
    "smartWaitFrameStrategy=fresh_frame_per_attempt_release_always_template_open_once",
    "smartWaitDeviceValidated=0"
)
foreach ($marker in $required) {
    if ($capability -notlike "*$marker*") { throw "Task 97 is missing '$marker': $capability" }
}

$resolvedPath = $ScriptPath
if (-not $resolvedPath) {
    $resolvedPath = if ($Runtime -eq "rootfull") {
        "/var/mobile/Library/TLinkauto/scripts/examples/Smart Wait Smoke.tl"
    }
    else {
        "/var/mobile/Library/TLinkauto/scripts/Compatibility Tests/09 Smart Wait.tl"
    }
}

$runState = "not_run"
$lastError = ""
if ($RunSmoke) {
    $start = Invoke-TLinkSmartWaitTask -Task "19$resolvedPath"
    if ($start -notlike "0*") { throw "Smart Wait smoke did not start: $start" }
    $runState = "started"
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 250
        $status = Get-TLinkSmartWaitStatus
        $lastError = [string]$status.script.last_error
        if (-not [bool]$status.script.is_playing) {
            $runState = [string]$status.script.state
            if (-not $runState) { $runState = "finished" }
            break
        }
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($runState -eq "started") { throw "Smart Wait smoke timed out while script remained active" }
    if ($lastError) { throw "Smart Wait smoke failed: $lastError" }
}

[pscustomobject]@{
    host = $HostIP
    runtime = $Runtime
    phase = 1
    state = "implemented"
    schema = "smart_wait_result_v1"
    capability_check = "passed"
    smoke_test_run = [bool]$RunSmoke
    smoke_script = $resolvedPath
    smoke_state = $runState
    last_error = $lastError
    device_validated = $false
} | Format-List
