[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [int]$TimeoutMs = 5000,
    [ValidateSet("observe", "enforced")]
    [string]$ExpectedMode = "observe",
    [string]$ExpectedState = ""
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
    try {
        $json = [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($Response.Substring(3).Trim())
        )
        return $json | ConvertFrom-Json
    }
    catch {
        throw "Invalid Base64 JSON response: $Response"
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected) {
        throw "$Label expected '$Expected', got '$Actual'"
    }
}

Write-Host "Checking rootfull Phase 2 lifecycle at ${HostIP}:$Port"

$hello = Invoke-TLinkTask -Task "97"
if ($hello -notlike "0;;*runtime=rootfull*license_phase=2*activationUI=1*runtimeGate=0*") {
    throw "Task 97 does not report rootfull Phase 2 lifecycle: $hello"
}

$expectedRootfullMode = if ($ExpectedMode -eq "enforced") {
    "enforced_marker_v1"
} else {
    "observe_marker_v1"
}
$expectedVerifierMode = if ($ExpectedMode -eq "enforced") {
    "enforced_compile_time_v1"
} else {
    "observe_compile_time_v1"
}

$daemonStatus = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "75")
$springBoardStatus = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "60")

Assert-Equal $daemonStatus.rootfull_license_phase 2 "daemon phase"
Assert-Equal $springBoardStatus.license.phase 2 "SpringBoard phase"
Assert-Equal ([bool]$daemonStatus.activation_lifecycle_active) $true "activation lifecycle"
Assert-Equal ([bool]$daemonStatus.runtime_gate_active) $false "daemon runtime gate"
Assert-Equal ([bool]$springBoardStatus.license.runtime_gate_active) $false "SpringBoard runtime gate"
Assert-Equal $daemonStatus.rootfull_build_mode $expectedRootfullMode "rootfull build mode"
Assert-Equal $daemonStatus.verifier_build_mode $expectedVerifierMode "verifier build mode"
Assert-Equal $daemonStatus.state $springBoardStatus.license.state "cross-process license state"
if ($ExpectedState) {
    Assert-Equal $daemonStatus.state $ExpectedState "license state"
}

$reloaded = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "76reload")
Assert-Equal $reloaded.generation_action "reload" "task 76 action"
Assert-Equal ([bool]$reloaded.cache_invalidated) $true "task 76 cache invalidation"

$safeProbe = Invoke-TLinkTask -Task "251"
if ($safeProbe -like "-1;;license_required*") {
    throw "Phase 2 unexpectedly enabled the runtime gate: $safeProbe"
}

[ordered]@{
    passed = $true
    host = $HostIP
    port = $Port
    phase = 2
    build_mode = $ExpectedMode
    state = $daemonStatus.state
    licensed = [bool]$daemonStatus.licensed
    effective_access = [bool]$daemonStatus.effective_access
    activation_lifecycle_active = [bool]$daemonStatus.activation_lifecycle_active
    runtime_gate_active = [bool]$daemonStatus.runtime_gate_active
    license_generation = [uint64]$daemonStatus.license_generation
    safe_probe_response = $safeProbe
} | ConvertTo-Json -Depth 6
