[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [int]$TimeoutMs = 6000,
    [int]$ExpectedPhase = 5,
    [ValidateSet("observe", "enforced")]
    [string]$ExpectedMode = "enforced",
    [string]$ExpectedState = "",
    [ValidateSet("allowed", "denied")]
    [string]$ExpectedAccess = "allowed",
    [ValidateRange(1, 500)]
    [int]$ProbeCount = 25,
    [double]$MaxFeatureCheckAverageUs = 5000,
    [double]$MaxStatusRefreshAverageMs = 150,
    [switch]$EnforcePerformanceBudget
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

Write-Host "Checking rootfull Phase 5 UI snapshot and verifier latency at ${HostIP}:$Port"

$hello = Invoke-TLinkTask -Task "97"
if ($hello -notlike "0;;*runtime=rootfull*license_phase=$ExpectedPhase*uiFeatureSnapshot=1*verifierMetrics=1*") {
    throw "Task 97 does not report the rootfull Phase 5 contract: $hello"
}

$before = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "75")
$springBoardStatus = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "60")
$expectedEnforcement = $ExpectedMode -eq "enforced"

Assert-Equal $before.rootfull_license_phase $ExpectedPhase "daemon phase"
Assert-Equal $springBoardStatus.license.phase $ExpectedPhase "SpringBoard phase"
Assert-Equal ([bool]$before.ui_feature_snapshot_active) $true "daemon UI snapshot flag"
Assert-Equal ([bool]$springBoardStatus.license.ui_feature_snapshot_active) $true "SpringBoard UI snapshot flag"
Assert-Equal ([bool]$before.runtime_gate_active) $true "daemon runtime gate"
Assert-Equal ([bool]$before.enforcement_enabled) $expectedEnforcement "enforcement mode"
Assert-Equal $before.state $springBoardStatus.license.state "cross-process state"
if ($ExpectedState) {
    Assert-Equal $before.state $ExpectedState "license state"
}

$responses = @()
$wallClock = [System.Diagnostics.Stopwatch]::StartNew()
for ($index = 0; $index -lt $ProbeCount; $index++) {
    $response = Invoke-TLinkTask -Task "250"
    $responses += $response
    $denied = $response -like "-1;;license_required*"
    if ($ExpectedAccess -eq "allowed" -and $denied) {
        throw "Automation probe $index was denied unexpectedly: $response"
    }
    if ($ExpectedAccess -eq "denied" -and -not $denied) {
        throw "Automation probe $index should be denied, got: $response"
    }
}
$wallClock.Stop()

$after = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "75")
$daemonPerf = $after.verifier_performance
$springBoardPerf = $springBoardStatus.license.verifier_performance
if ($null -eq $daemonPerf) {
    throw "Task 75 is missing verifier_performance"
}
if ($null -eq $springBoardPerf) {
    throw "Task 60 is missing verifier_performance"
}

$checkDelta = [long]$daemonPerf.feature_check_count - [long]$before.verifier_performance.feature_check_count
if ($checkDelta -lt $ProbeCount) {
    throw "Expected at least $ProbeCount verifier checks, observed delta $checkDelta"
}

$featureAverageUs = [double]$daemonPerf.feature_check_average_us
$statusAverageMs = [double]$daemonPerf.status_refresh_average_ms
$featureBudgetPassed = $featureAverageUs -le $MaxFeatureCheckAverageUs
$statusBudgetPassed = $statusAverageMs -le $MaxStatusRefreshAverageMs
$budgetPassed = $featureBudgetPassed -and $statusBudgetPassed
if ($EnforcePerformanceBudget -and -not $budgetPassed) {
    throw ("License latency budget exceeded: feature average {0:N2} us (limit {1:N2}), " +
        "status refresh average {2:N2} ms (limit {3:N2})" -f
        $featureAverageUs, $MaxFeatureCheckAverageUs, $statusAverageMs, $MaxStatusRefreshAverageMs)
}

[ordered]@{
    passed = $true
    host = $HostIP
    port = $Port
    phase = $ExpectedPhase
    build_mode = $ExpectedMode
    state = $after.state
    effective_access = [bool]$after.effective_access
    ui_feature_snapshot_active = [bool]$after.ui_feature_snapshot_active
    probe_count = $ProbeCount
    probe_wall_clock_total_ms = [math]::Round($wallClock.Elapsed.TotalMilliseconds, 3)
    probe_wall_clock_average_ms = [math]::Round(
        $wallClock.Elapsed.TotalMilliseconds / $ProbeCount,
        3
    )
    verifier_check_delta = $checkDelta
    verifier_performance = $daemonPerf
    springboard_verifier_performance = $springBoardPerf
    performance_budget = [ordered]@{
        enforced = [bool]$EnforcePerformanceBudget
        passed = $budgetPassed
        max_feature_check_average_us = $MaxFeatureCheckAverageUs
        max_status_refresh_average_ms = $MaxStatusRefreshAverageMs
        feature_check_passed = $featureBudgetPassed
        status_refresh_passed = $statusBudgetPassed
    }
    note = "Network activation/refresh is outside the feature-check hot path."
} | ConvertTo-Json -Depth 8
