[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [int]$TimeoutMs = 5000,
    [ValidateSet("observe", "enforced")]
    [string]$ExpectedMode = "enforced",
    [string]$ExpectedState = "",
    [switch]$RunSafeFeatureProbes
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkTask {
    param([Parameter(Mandatory = $true)][string]$Task)

    $client = [System.Net.Sockets.TcpClient]::new()
    $client.ReceiveTimeout = $TimeoutMs
    $client.SendTimeout = $TimeoutMs
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
        if ($null -eq $line) { throw "Port $Port closed without a response for task $Task" }
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

    if (-not $Response.StartsWith("0;;")) { throw "Expected success response, got: $Response" }
    $encoded = $Response.Substring(3).Trim()
    try {
        $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
        return $json | ConvertFrom-Json
    }
    catch {
        throw "Invalid Base64 JSON response: $Response"
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected) { throw "$Label expected '$Expected', got '$Actual'" }
}

function Assert-FeatureProbe {
    param([string]$Feature, [string]$Task, [bool]$ShouldAllow)
    $response = Invoke-TLinkTask -Task $Task
    $denied = $response -like "-1;;license_required*feature=$Feature*"
    if ($ShouldAllow -and $denied) { throw "$Feature was unexpectedly denied: $response" }
    if (-not $ShouldAllow -and -not $denied) { throw "$Feature was unexpectedly allowed: $response" }
    [pscustomobject]@{
        feature = $Feature
        allowed = -not $denied
        operation_success = $response.StartsWith("0;;")
        response = $response
    }
}

Write-Host "Checking TLinkauto license diagnostics at ${HostIP}:$Port"
$helloRaw = Invoke-TLinkTask -Task "97"
if ($helloRaw -notlike "0;;*serviceVersion=23*") { throw "Task 97 does not report serviceVersion=23: $helloRaw" }
$expectedMarker = if ($ExpectedMode -eq "enforced") { "enforced_compile_time_v1" } else { "observe_compile_time_v1" }
if ($helloRaw -notlike "*licenseBuildMode=$expectedMarker*") { throw "Task 97 does not report $expectedMarker" }

$hello = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "60")
$status = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "75")
Assert-Equal $hello.service_version 23 "service_version"
Assert-Equal $hello.license_contract_version 1 "hello license_contract_version"
Assert-Equal $status.license_contract_version 1 "status license_contract_version"
Assert-Equal $status.build_mode $expectedMarker "build_mode"
Assert-Equal ([bool]$status.enforcement_enabled) ($ExpectedMode -eq "enforced") "enforcement_enabled"
if ($ExpectedState) { Assert-Equal $status.state $ExpectedState "license state" }

$generationBefore = [uint64]$status.license_generation
$reloaded = ConvertFrom-TLinkBase64Response (Invoke-TLinkTask -Task "76reload")
Assert-Equal $reloaded.generation_action "reload" "task 76 action"
Assert-Equal ([uint64]$reloaded.license_generation) $generationBefore "reload generation"

$probeResults = @()
if ($RunSafeFeatureProbes) {
    $licensed = [bool]$status.licensed
    $features = @($status.features)
    foreach ($probe in @(
        @{ Feature = "automation"; Task = "251" },
        @{ Feature = "script"; Task = "20" },
        @{ Feature = "admin"; Task = "31" },
        @{ Feature = "shell"; Task = "13echo tlink-license-phase6" }
    )) {
        $shouldAllow = $ExpectedMode -eq "observe" -or ($licensed -and ($features -contains "all" -or $features -contains $probe.Feature))
        $probeResults += Assert-FeatureProbe -Feature $probe.Feature -Task $probe.Task -ShouldAllow $shouldAllow
    }
}

$summary = [ordered]@{
    passed = $true
    host = $HostIP
    port = $Port
    service_version = $hello.service_version
    build_mode = $status.build_mode
    state = $status.state
    licensed = [bool]$status.licensed
    effective_access = [bool]$status.effective_access
    generation = [uint64]$status.license_generation
    features = @($status.features)
    probes = $probeResults
}
$summary | ConvertTo-Json -Depth 8
