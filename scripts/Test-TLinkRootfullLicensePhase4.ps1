[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [int]$TimeoutMs = 6000,
    [ValidateSet("observe", "enforced")]
    [string]$ExpectedMode = "enforced",
    [string]$ExpectedState = "",
    [ValidateSet("allowed", "denied")]
    [string]$ExpectedAccess = "allowed",
    [switch]$ProbeH264,
    [int]$H264Port = 7001,
    [string]$LongRunningScriptBundlePath = ""
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkTask {
    param([Parameter(Mandatory = $true)][string]$Task)

    $client = [System.Net.Sockets.TcpClient]::new()
    $client.ReceiveTimeout = $TimeoutMs
    $client.SendTimeout = $TimeoutMs
    $reader = $null
    $writer = $null
    $stream = $null
    try {
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $encoding = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($stream, $encoding, 1024, $true)
        $writer.NewLine = "`r`n"
        $writer.AutoFlush = $true
        $reader = [System.IO.StreamReader]::new($stream, $encoding, $false, 1024, $true)
        $writer.WriteLine($Task)
        $line = $reader.ReadLine()
        if ($null -eq $line) {
            throw "Port $Port closed without a response for task $Task"
        }
        return $line
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($writer) { $writer.Dispose() }
        if ($stream) { $stream.Dispose() }
        $client.Dispose()
    }
}

function ConvertFrom-TLinkBase64Response {
    param([Parameter(Mandatory = $true)][string]$Response)

    if (-not $Response.StartsWith("0;;")) {
        throw "Expected success response, got: $Response"
    }
    $json = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($Response.Substring(3).Trim())
    )
    return $json | ConvertFrom-Json
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected) {
        throw "$Label expected '$Expected', got '$Actual'"
    }
}

Write-Host "Checking rootfull Phase 4 component gates at ${HostIP}:$Port"

$hello = Invoke-TLinkTask -Task "97"
if ($hello -notlike "0;;*runtime=rootfull*license_phase=4*runtimeGate=1*gateScope=task_and_long_running_component*") {
    throw "Task 97 does not report the rootfull Phase 4 gate: $hello"
}

$daemonStatus = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "75")
$springBoardStatus = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "60")
$expectedEnforcement = $ExpectedMode -eq "enforced"

Assert-Equal $daemonStatus.rootfull_license_phase 4 "daemon phase"
Assert-Equal $springBoardStatus.license.phase 4 "SpringBoard phase"
Assert-Equal $daemonStatus.enforcement_scope "task_and_long_running_component_gate" "daemon scope"
Assert-Equal $springBoardStatus.license.enforcement_scope "task_and_long_running_component_gate" "SpringBoard scope"
Assert-Equal ([bool]$daemonStatus.runtime_gate_active) $true "daemon runtime gate"
Assert-Equal ([bool]$springBoardStatus.license.runtime_gate_active) $true "SpringBoard runtime gate"
Assert-Equal ([bool]$daemonStatus.h264_gate_active) $true "daemon H264 gate"
Assert-Equal $daemonStatus.h264_heartbeat_interval_ms 5000 "daemon H264 heartbeat"
Assert-Equal ([bool]$daemonStatus.script_heartbeat_active) $true "daemon script heartbeat"
Assert-Equal ([bool]$daemonStatus.scheduler_launch_gate_active) $true "daemon scheduler gate"
Assert-Equal ([bool]$daemonStatus.helper_runtime_gate_active) $true "daemon helper gate"
Assert-Equal ([bool]$springBoardStatus.license.h264_gate_active) $true "SpringBoard H264 gate"
Assert-Equal $springBoardStatus.license.h264_heartbeat_interval_ms 5000 "SpringBoard H264 heartbeat"
Assert-Equal ([bool]$springBoardStatus.license.script_heartbeat_active) $true "SpringBoard script heartbeat"
Assert-Equal ([bool]$springBoardStatus.license.scheduler_launch_gate_active) $true "SpringBoard scheduler gate"
Assert-Equal ([bool]$springBoardStatus.license.helper_runtime_gate_active) $true "SpringBoard helper gate"
Assert-Equal ([bool]$daemonStatus.enforcement_enabled) $expectedEnforcement "enforcement mode"
Assert-Equal $daemonStatus.state $springBoardStatus.license.state "cross-process state"
if ($ExpectedState) {
    Assert-Equal $daemonStatus.state $ExpectedState "license state"
}

$scriptProbe = $null
if ($LongRunningScriptBundlePath) {
    $scriptProbe = Invoke-TLinkTask -Task "19$LongRunningScriptBundlePath"
    if ($ExpectedAccess -eq "denied") {
        if ($scriptProbe -notlike "-1;;license_required*feature=script*") {
            throw "Script start should be denied, got: $scriptProbe"
        }
    }
    else {
        if ($scriptProbe -like "-1;;license_required*") {
            throw "Script start should pass the license gate, got: $scriptProbe"
        }
        Start-Sleep -Seconds 2
        $runningStatus = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "60")
        if (-not [bool]$runningStatus.script.license_runtime.heartbeat_active) {
            throw "The supplied script did not remain active long enough to observe its heartbeat"
        }
    }
}

$h264Probe = $null
if ($ProbeH264) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = $TimeoutMs
        $client.Connect($HostIP, $H264Port)
        $stream = $client.GetStream()
        $buffer = [byte[]]::new(1)
        $read = $stream.Read($buffer, 0, 1)
        $h264Probe = [ordered]@{ port = $H264Port; bytes_read = $read }
        if ($ExpectedAccess -eq "denied" -and $read -ne 0) {
            throw "H264 should close immediately for denied stream feature"
        }
        if ($ExpectedAccess -eq "allowed" -and $read -le 0) {
            throw "H264 closed unexpectedly; ensure no other viewer owns the single client slot"
        }
    }
    finally {
        if ($stream) { $stream.Dispose() }
        $client.Dispose()
    }
}

[ordered]@{
    passed = $true
    host = $HostIP
    port = $Port
    phase = 4
    build_mode = $ExpectedMode
    state = $daemonStatus.state
    effective_access = [bool]$daemonStatus.effective_access
    enforcement_scope = $daemonStatus.enforcement_scope
    h264_heartbeat_interval_ms = $daemonStatus.h264_heartbeat_interval_ms
    script_heartbeat_active = [bool]$daemonStatus.script_heartbeat_active
    scheduler_launch_gate_active = [bool]$daemonStatus.scheduler_launch_gate_active
    helper_runtime_gate_active = [bool]$daemonStatus.helper_runtime_gate_active
    script_probe = $scriptProbe
    h264_probe = $h264Probe
} | ConvertTo-Json -Depth 7
