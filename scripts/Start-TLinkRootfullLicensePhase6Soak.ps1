[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [double]$DurationHours = 24,
    [int]$IntervalSeconds = 60,
    [int]$TimeoutMs = 6000,
    [ValidateSet("observe", "enforced")]
    [string]$ExpectedMode = "enforced",
    [string]$ExpectedState = "",
    [int]$MaxConsecutiveFailures = 5,
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
if ($DurationHours -le 0) { throw "DurationHours must be positive" }
if ($IntervalSeconds -lt 5) { throw "IntervalSeconds must be at least 5" }
if (-not $OutputPath) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path (Get-Location) "rootfull-license-phase6-soak-$stamp.jsonl"
}

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
        if ($null -eq $line) { throw "connection closed without a response" }
        return $line
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($writer) { $writer.Dispose() }
        if ($stream) { $stream.Dispose() }
        $client.Dispose()
    }
}

function ConvertFrom-TLinkStatus {
    param([string]$Response)
    if (-not $Response.StartsWith("0;;")) { throw $Response }
    $json = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($Response.Substring(3).Trim())
    )
    return $json | ConvertFrom-Json
}

function Write-Sample {
    param([hashtable]$Sample)
    $line = ($Sample | ConvertTo-Json -Compress -Depth 12) + [Environment]::NewLine
    [IO.File]::AppendAllText(
        $OutputPath,
        $line,
        [Text.UTF8Encoding]::new($false)
    )
}

$started = [DateTimeOffset]::UtcNow
$deadline = $started.AddHours($DurationHours)
$consecutiveFailures = 0
$sampleCount = 0
$expectedRootfullMode = "rootfull_${ExpectedMode}_compile_time_v1"
$expectedVerifierMode = "${ExpectedMode}_compile_time_v1"
Write-Host "Writing rootfull Phase 6 soak evidence to $OutputPath"

while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $sampleCount++
    $now = [DateTimeOffset]::UtcNow
    try {
        $hello = Invoke-TLinkTask -Task "97"
        $daemon = ConvertFrom-TLinkStatus (Invoke-TLinkTask -Task "75")
        $springBoard = ConvertFrom-TLinkStatus (Invoke-TLinkTask -Task "60")
        if ($hello -notlike "0;;*license_phase=6*releaseIntegrity=1*antiRollback=1*") {
            throw "task97_phase6_marker_missing"
        }
        if ($daemon.rootfull_license_phase -ne 6) {
            throw "daemon_phase=$($daemon.rootfull_license_phase)"
        }
        if ($springBoard.license.phase -ne 6) {
            throw "springboard_phase=$($springBoard.license.phase)"
        }
        if ($daemon.rootfull_build_mode -ne $expectedRootfullMode) {
            throw "daemon_rootfull_mode=$($daemon.rootfull_build_mode)"
        }
        if ($daemon.verifier_build_mode -ne $expectedVerifierMode) {
            throw "daemon_verifier_mode=$($daemon.verifier_build_mode)"
        }
        if (-not [bool]$daemon.release_integrity.valid) {
            throw "release_integrity=$($daemon.release_integrity.state)"
        }
        if ($daemon.licensed -and -not [bool]$daemon.anti_rollback.valid) {
            throw "anti_rollback=$($daemon.anti_rollback.state)"
        }
        if ($daemon.state -ne $springBoard.license.state) {
            throw "state_split daemon=$($daemon.state) springboard=$($springBoard.license.state)"
        }
        if ($ExpectedState -and $daemon.state -ne $ExpectedState) {
            throw "state=$($daemon.state)"
        }

        $consecutiveFailures = 0
        Write-Sample @{
            schema_version = 1
            timestamp_utc = $now.ToString("o")
            ok = $true
            sample = $sampleCount
            phase = 6
            state = $daemon.state
            licensed = [bool]$daemon.licensed
            effective_access = [bool]$daemon.effective_access
            generation = [uint64]$daemon.license_generation
            rootfull_build_mode = $daemon.rootfull_build_mode
            verifier_build_mode = $daemon.verifier_build_mode
            release_integrity = $daemon.release_integrity
            anti_rollback = $daemon.anti_rollback
            verifier_performance = $daemon.verifier_performance
            expires_at = $daemon.expires_at
            offline_until = $daemon.offline_until
        }
    }
    catch {
        $consecutiveFailures++
        Write-Sample @{
            schema_version = 1
            timestamp_utc = $now.ToString("o")
            ok = $false
            sample = $sampleCount
            consecutive_failures = $consecutiveFailures
            error = $_.Exception.Message
        }
        if ($consecutiveFailures -ge $MaxConsecutiveFailures) {
            throw "Soak aborted after $consecutiveFailures consecutive failures. Evidence: $OutputPath"
        }
    }
    Start-Sleep -Seconds $IntervalSeconds
}

Write-Host "Soak completed: $sampleCount samples, evidence $OutputPath"
