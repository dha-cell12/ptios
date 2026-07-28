[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [int]$TimeoutMs = 6000,
    [int]$ExpectedPhase = 6,
    [ValidateSet("observe", "enforced")]
    [string]$ExpectedMode = "enforced",
    [string]$ExpectedState = "",
    [ValidateSet("allowed", "denied")]
    [string]$ExpectedAccess = "allowed",
    [switch]$RunSafeFeatureProbes,
    [ValidateRange(1, 500)]
    [int]$PerformanceProbeCount = 25,
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

function Test-FeatureProbe {
    param(
        [string]$Feature,
        [string]$Task
    )
    $response = Invoke-TLinkTask -Task $Task
    $denied = $response -like "-1;;license_required*"
    if ($ExpectedAccess -eq "allowed" -and $denied) {
        throw "$Feature probe was denied unexpectedly: $response"
    }
    if ($ExpectedAccess -eq "denied" -and -not $denied) {
        throw "$Feature probe should be denied: $response"
    }
    return [ordered]@{
        feature = $Feature
        denied = $denied
        response = $response
    }
}

Write-Host "Checking rootfull Phase 6 release hardening at ${HostIP}:$Port"

$hello = Invoke-TLinkTask -Task "97"
if ($hello -notlike "0;;*runtime=rootfull*license_phase=$ExpectedPhase*releaseIntegrity=1*antiRollback=1*") {
    throw "Task 97 does not report the rootfull Phase 6 contract: $hello"
}

$daemon = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "75")
$springBoard = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "60")
$expectedEnforcement = $ExpectedMode -eq "enforced"
$expectedRootfullMode = "rootfull_${ExpectedMode}_compile_time_v1"
$expectedVerifierMode = "${ExpectedMode}_compile_time_v1"

Assert-Equal $daemon.rootfull_license_phase $ExpectedPhase "daemon phase"
Assert-Equal $springBoard.license.phase $ExpectedPhase "SpringBoard phase"
Assert-Equal ([bool]$daemon.enforcement_enabled) $expectedEnforcement "enforcement mode"
Assert-Equal $daemon.rootfull_build_mode $expectedRootfullMode "daemon rootfull build mode"
Assert-Equal $daemon.verifier_build_mode $expectedVerifierMode "daemon verifier build mode"
Assert-Equal $springBoard.license.rootfull_build_mode $expectedRootfullMode "SpringBoard rootfull build mode"
Assert-Equal $springBoard.license.verifier_build_mode $expectedVerifierMode "SpringBoard verifier build mode"
Assert-Equal $daemon.state $springBoard.license.state "cross-process state"
if ($ExpectedState) {
    Assert-Equal $daemon.state $ExpectedState "license state"
}

Assert-Equal ([bool]$daemon.release_integrity_active) $true "daemon integrity flag"
Assert-Equal ([bool]$springBoard.license.release_integrity_active) $true "SpringBoard integrity flag"
Assert-Equal ([bool]$daemon.release_integrity.valid) $true "daemon release integrity"
Assert-Equal ([bool]$springBoard.license.release_integrity.valid) $true "SpringBoard release integrity"
Assert-Equal $daemon.release_integrity.state "coherent" "daemon release integrity state"
Assert-Equal $springBoard.license.release_integrity.state "coherent" "SpringBoard release integrity state"

Assert-Equal ([bool]$daemon.anti_rollback_active) $true "daemon anti-rollback flag"
Assert-Equal ([bool]$springBoard.license.anti_rollback_active) $true "SpringBoard anti-rollback flag"
if ($daemon.licensed) {
    Assert-Equal ([bool]$daemon.anti_rollback.valid) $true "daemon anti-rollback"
    if ($daemon.anti_rollback.state -notin @("created", "advanced", "valid")) {
        throw "Unexpected daemon anti-rollback state: $($daemon.anti_rollback.state)"
    }
}

$probes = @()
if ($RunSafeFeatureProbes) {
    $probes += Test-FeatureProbe -Feature "automation" -Task "250"
    $probes += Test-FeatureProbe -Feature "script" -Task "20"
    $probes += Test-FeatureProbe -Feature "admin" -Task "31"
    $probes += Test-FeatureProbe -Feature "shell" -Task "13"
}

$beforeChecks = [long]$daemon.verifier_performance.feature_check_count
$timer = [System.Diagnostics.Stopwatch]::StartNew()
for ($index = 0; $index -lt $PerformanceProbeCount; $index++) {
    $null = Test-FeatureProbe -Feature "automation" -Task "250"
}
$timer.Stop()
$after = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "75")
$performance = $after.verifier_performance
$checkDelta = [long]$performance.feature_check_count - $beforeChecks
if ($checkDelta -lt $PerformanceProbeCount) {
    throw "Expected $PerformanceProbeCount verifier checks, observed $checkDelta"
}

$featureAverageUs = [double]$performance.feature_check_average_us
$statusAverageMs = [double]$performance.status_refresh_average_ms
$budgetPassed =
    $featureAverageUs -le $MaxFeatureCheckAverageUs -and
    $statusAverageMs -le $MaxStatusRefreshAverageMs
if ($EnforcePerformanceBudget -and -not $budgetPassed) {
    throw ("Latency budget exceeded: check {0:N2} us/{1:N2}, verify {2:N2} ms/{3:N2}" -f
        $featureAverageUs,
        $MaxFeatureCheckAverageUs,
        $statusAverageMs,
        $MaxStatusRefreshAverageMs)
}

[ordered]@{
    passed = $true
    host = $HostIP
    port = $Port
    phase = $ExpectedPhase
    build_mode = $ExpectedMode
    state = $after.state
    effective_access = [bool]$after.effective_access
    release_integrity = $after.release_integrity
    anti_rollback = $after.anti_rollback
    verifier_performance = $performance
    performance_probe = [ordered]@{
        count = $PerformanceProbeCount
        wall_clock_total_ms = [math]::Round($timer.Elapsed.TotalMilliseconds, 3)
        wall_clock_average_ms = [math]::Round(
            $timer.Elapsed.TotalMilliseconds / $PerformanceProbeCount,
            3
        )
        verifier_check_delta = $checkDelta
        budget_enforced = [bool]$EnforcePerformanceBudget
        budget_passed = $budgetPassed
    }
    feature_probes = $probes
} | ConvertTo-Json -Depth 10
