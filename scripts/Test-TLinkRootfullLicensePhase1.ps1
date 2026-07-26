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
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($stream, $utf8NoBom, 1024, $true)
        $writer.NewLine = "`r`n"
        $writer.AutoFlush = $true
        $reader = [System.IO.StreamReader]::new($stream, $utf8NoBom, $false, 1024, $true)
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
        $encoded = $Response.Substring(3).Trim()
        $json = [System.Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($encoded)
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

Write-Host "Checking rootfull Phase 1 diagnostics at ${HostIP}:$Port"

$helloRaw = Invoke-TLinkTask -Task "97"
if ($helloRaw -notlike "0;;*runtime=rootfull*license_phase=1*runtimeGate=0*") {
    throw "Task 97 does not report rootfull Phase 1 observe mode: $helloRaw"
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

$status = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "75")
Assert-Equal $status.license_contract_version 1 "license_contract_version"
Assert-Equal $status.rootfull_license_phase 1 "rootfull_license_phase"
Assert-Equal $status.runtime "rootfull" "runtime"
Assert-Equal ([bool]$status.runtime_gate_active) $false "runtime_gate_active"
Assert-Equal $status.enforcement_scope "observe_verifier_no_runtime_gate" "enforcement_scope"
Assert-Equal $status.rootfull_build_mode $expectedRootfullMode "rootfull_build_mode"
Assert-Equal $status.verifier_build_mode $expectedVerifierMode "verifier_build_mode"
if ($ExpectedState) {
    Assert-Equal $status.state $ExpectedState "license state"
}

$generationBefore = [uint64]$status.license_generation
$advanced = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "76")
Assert-Equal $advanced.generation_action "advance" "task 76 advance action"
Assert-Equal ([uint64]$advanced.generation_before) $generationBefore "generation_before"
Assert-Equal ([uint64]$advanced.license_generation) ($generationBefore + 1) "advanced generation"

$reloaded = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "76reload")
Assert-Equal $reloaded.generation_action "reload" "task 76 reload action"
Assert-Equal ([bool]$reloaded.cache_invalidated) $true "cache_invalidated"
Assert-Equal ([uint64]$reloaded.license_generation) ([uint64]$advanced.license_generation) "reload generation"

[ordered]@{
    passed = $true
    host = $HostIP
    port = $Port
    phase = 1
    build_mode = $ExpectedMode
    state = $status.state
    configured = [bool]$status.configured
    licensed = [bool]$status.licensed
    effective_access = [bool]$status.effective_access
    runtime_gate_active = [bool]$status.runtime_gate_active
    generation_before = $generationBefore
    generation_after = [uint64]$advanced.license_generation
    source = $status.source
} | ConvertTo-Json -Depth 6
