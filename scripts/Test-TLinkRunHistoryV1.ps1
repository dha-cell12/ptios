param(
    [Parameter(Mandatory = $true)][string]$HostIP,
    [Parameter(Mandatory = $true)][ValidateSet("rootfull", "trollstore")][string]$Runtime,
    [int]$Port = 6000,
    [switch]$RunFailureSmoke,
    [string]$ScriptPath = ""
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkRunHistoryTask {
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
            while ($response.Length -lt 1048576) {
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

function Get-TLinkRunHistoryStatus {
    $raw = Invoke-TLinkRunHistoryTask -Task "60"
    if ($raw -notlike "0;;*") { throw "Task 60 failed: $raw" }
    $b64 = ($raw -split ";;", 2)[1]
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json
}

$capability = Invoke-TLinkRunHistoryTask -Task "97"
$required = @(
    "runtime=$Runtime",
    "runHistoryState=implemented",
    "runHistoryVersion=1",
    "runHistorySchema=run_history_v1",
    "failureEvidenceSchema=failure_evidence_v1",
    "runHistoryTransport=task60_status_json_v1",
    "runHistoryRetentionMaxRuns=50",
    "failureEvidenceScreenshot=best_effort_png_on_failure",
    "runHistoryDeviceValidated=0"
)
foreach ($marker in $required) {
    if ($capability -notlike "*$marker*") { throw "Task 97 is missing '$marker': $capability" }
}

$status = Get-TLinkRunHistoryStatus
if ($status.run_history.schema -ne "run_history_v1") { throw "task 60 run_history schema mismatch" }

$resolvedPath = $ScriptPath
if (-not $resolvedPath) {
    $resolvedPath = if ($Runtime -eq "rootfull") {
        "/var/mobile/Library/TLinkauto/scripts/examples/Failure Evidence Smoke.tl"
    } else {
        "/var/mobile/Library/TLinkauto/scripts/Compatibility Tests/10 Failure Evidence.tl"
    }
}

$evidence = $null
if ($RunFailureSmoke) {
    $beforeIds = @($status.run_history.runs | ForEach-Object { [string]$_.run_id })
    $start = Invoke-TLinkRunHistoryTask -Task "19$resolvedPath"
    if ($start -notlike "0*") { throw "Failure smoke did not start: $start" }
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    do {
        Start-Sleep -Milliseconds 300
        $status = Get-TLinkRunHistoryStatus
        $run = @($status.run_history.runs | Where-Object {
            $beforeIds -notcontains [string]$_.run_id -and [string]$_.state -notin @("running", "starting")
        }) | Select-Object -First 1
        if ($run) { break }
    } while ([DateTime]::UtcNow -lt $deadline)

    if (-not $run) { throw "No terminal history record appeared for failure smoke" }
    if ($run.state -ne "failed") { throw "Expected failed history state, got '$($run.state)'" }
    if ([string]$run.error -notlike "*intentional_failure_evidence_smoke_v1*") { throw "Primary error missing: $($run.error)" }
    $evidence = $run.failure_evidence
    if ($evidence.schema -ne "failure_evidence_v1") { throw "failure evidence schema mismatch" }
    if (-not $evidence.metadata_path) { throw "failure evidence metadata path missing" }
    if (@($evidence.log_tail).Count -eq 0) { throw "failure evidence log tail missing" }
    if (-not [bool]$evidence.screenshot_captured -and -not [string]$evidence.screenshot_error) {
        throw "failure evidence must contain screenshot or explicit screenshot_error"
    }
}

[pscustomobject]@{
    host = $HostIP
    runtime = $Runtime
    schema = [string]$status.run_history.schema
    total_count = [int]$status.run_history.total_count
    failed_count = [int]$status.run_history.failed_count
    failure_smoke_run = [bool]$RunFailureSmoke
    evidence_metadata = if ($evidence) { [string]$evidence.metadata_path } else { "" }
    screenshot_captured = if ($evidence) { [bool]$evidence.screenshot_captured } else { $false }
    screenshot_error = if ($evidence) { [string]$evidence.screenshot_error } else { "" }
    device_validated = $false
} | Format-List
