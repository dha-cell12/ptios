[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [int]$TimeoutMs = 5000,
    [ValidateSet("observe", "enforced")]
    [string]$ExpectedMode = "enforced",
    [string]$ExpectedState = "",
    [ValidateSet("allowed", "denied")]
    [string]$ExpectedAccess = "allowed",
    [ValidateSet("automation", "script", "admin", "shell")]
    [string[]]$ExpectedDeniedFeatures = @()
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

Write-Host "Checking rootfull Phase 3 task gates at ${HostIP}:$Port"

$hello = Invoke-TLinkTask -Task "97"
if ($hello -notlike "0;;*runtime=rootfull*license_phase=3*runtimeGate=1*taskPolicy=rootfull_explicit_v1*") {
    throw "Task 97 does not report the rootfull Phase 3 gate: $hello"
}

$daemonStatus = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "75")
$springBoardStatus = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "60")
$expectedEnforcement = $ExpectedMode -eq "enforced"

Assert-Equal $daemonStatus.rootfull_license_phase 3 "daemon phase"
Assert-Equal $springBoardStatus.license.phase 3 "SpringBoard phase"
Assert-Equal ([bool]$daemonStatus.runtime_gate_active) $true "daemon runtime gate"
Assert-Equal ([bool]$springBoardStatus.license.runtime_gate_active) $true "SpringBoard runtime gate"
Assert-Equal $daemonStatus.enforcement_scope "task_server_and_springboard_feature_gate" "daemon scope"
Assert-Equal $springBoardStatus.license.enforcement_scope "task_server_and_springboard_feature_gate" "SpringBoard scope"
Assert-Equal ([bool]$daemonStatus.enforcement_enabled) $expectedEnforcement "enforcement mode"
Assert-Equal $daemonStatus.state $springBoardStatus.license.state "cross-process state"
if ($ExpectedState) {
    Assert-Equal $daemonStatus.state $ExpectedState "license state"
}

$reloadStatus = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "76reload")
Assert-Equal $reloadStatus.generation_action "reload" "generation reload"
Assert-Equal ([bool]$reloadStatus.cache_invalidated) $true "cache invalidation"

$missingPolicyResponse = Invoke-TLinkTask -Task "74"
if ($missingPolicyResponse -ne "-1;;license_policy_missing task=74") {
    throw "Unknown rootfull task 74 must fail closed, got: $missingPolicyResponse"
}

$probes = [ordered]@{
    automation = "250"
    script = "37"
    admin = "31"
    shell = "13"
}
$probeResults = @()
foreach ($feature in $probes.Keys) {
    $response = Invoke-TLinkTask -Task $probes[$feature]
    $shouldDeny = $ExpectedAccess -eq "denied" -or $ExpectedDeniedFeatures -contains $feature
    if ($shouldDeny) {
        if ($response -notlike "-1;;license_required task=*feature=$feature*") {
            throw "$feature should be denied by license, got: $response"
        }
    }
    elseif ($response -like "-1;;license_required*" -or $response -like "-1;;license_policy_missing*") {
        throw "$feature should pass the Phase 3 license gate, got: $response"
    }
    $probeResults += [ordered]@{
        feature = $feature
        expected = if ($shouldDeny) { "denied" } else { "allowed" }
        response = $response
    }
}

[ordered]@{
    passed = $true
    host = $HostIP
    port = $Port
    phase = 3
    build_mode = $ExpectedMode
    state = $daemonStatus.state
    licensed = [bool]$daemonStatus.licensed
    effective_access = [bool]$daemonStatus.effective_access
    runtime_gate_active = [bool]$daemonStatus.runtime_gate_active
    task_policy = $daemonStatus.task_policy
    license_generation = [uint64]$daemonStatus.license_generation
    task10_license_drop_count = [uint64]$daemonStatus.task10_license_drop_count
    missing_policy_probe = $missingPolicyResponse
    probes = $probeResults
} | ConvertTo-Json -Depth 7
