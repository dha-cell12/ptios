[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [double]$DurationHours = 24,
    [int]$IntervalSeconds = 60,
    [int]$TimeoutMs = 5000,
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
    $OutputPath = Join-Path (Get-Location) "tlink-license-soak-$stamp.jsonl"
}

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
    $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Response.Substring(3).Trim()))
    return $json | ConvertFrom-Json
}

function Write-Sample {
    param([hashtable]$Sample)
    $line = $Sample | ConvertTo-Json -Compress -Depth 10
    Add-Content -LiteralPath $OutputPath -Value $line -Encoding UTF8
}

$started = [DateTimeOffset]::UtcNow
$deadline = $started.AddHours($DurationHours)
$consecutiveFailures = 0
$sampleCount = 0
$expectedMarker = if ($ExpectedMode -eq "enforced") { "enforced_compile_time_v1" } else { "observe_compile_time_v1" }
Write-Host "Writing license soak evidence to $OutputPath"

while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $sampleCount++
    $now = [DateTimeOffset]::UtcNow
    try {
        $helloRaw = Invoke-TLinkTask -Task "97"
        $hello = ConvertFrom-TLinkStatus (Invoke-TLinkTask -Task "60")
        $status = ConvertFrom-TLinkStatus (Invoke-TLinkTask -Task "75")
        if ($hello.service_version -ne 23) { throw "service_version=$($hello.service_version)" }
        if ($status.build_mode -ne $expectedMarker) { throw "build_mode=$($status.build_mode)" }
        if ($ExpectedState -and $status.state -ne $ExpectedState) { throw "state=$($status.state)" }
        if ($helloRaw -notlike "0;;*serviceVersion=23*") { throw "task97_service_marker_missing" }
        $consecutiveFailures = 0
        Write-Sample @{
            schema_version = 1
            timestamp_utc = $now.ToString("o")
            ok = $true
            sample = $sampleCount
            pid = $hello.pid
            service_version = $hello.service_version
            launch_executable_path = $hello.launch_executable_path
            build_mode = $status.build_mode
            state = $status.state
            licensed = [bool]$status.licensed
            effective_access = [bool]$status.effective_access
            generation = [uint64]$status.license_generation
            expires_at = $status.expires_at
            offline_until = $status.offline_until
            last_checked_at_ms = $status.last_checked_at_ms
            task10_drop_count = $hello.license_enforcement.task10_drop_count
            lifecycle_state = $hello.license_lifecycle.state
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
