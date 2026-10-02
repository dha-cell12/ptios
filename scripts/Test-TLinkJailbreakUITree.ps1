[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$HostIP,
    [Parameter(Mandatory = $true)][ValidateSet("rootfull", "roothide")][string]$Runtime,
    [ValidateRange(1, 65535)][int]$Port = 6000,
    [ValidateRange(1000, 60000)][int]$TimeoutMs = 10000,
    [ValidateRange(1, 1000)][int]$MaxElements = 250,
    [ValidateRange(1, 100)][int]$RepeatCount = 1,
    [ValidateRange(0, 10000)][int]$IntervalMs = 0,
    [ValidateRange(1, 1000)][int]$MinElements = 1,
    [string]$ExpectedBundle = "",
    [string]$Text = "",
    [string]$Identifier = "",
    [string]$Role = "",
    [ValidateSet("contains", "exact", "prefix")][string]$Match = "contains",
    [switch]$RequireMatch,
    [Nullable[double]]$AtX = $null,
    [Nullable[double]]$AtY = $null,
    [switch]$RequireHit,
    [switch]$RequireComplete,
    [switch]$Tap
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkUITask {
    param([Parameter(Mandatory = $true)][string]$Task)

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $connect = $client.BeginConnect($HostIP, $Port, $null, $null)
        try {
            if (-not $connect.AsyncWaitHandle.WaitOne($TimeoutMs)) {
                throw "Timed out connecting to ${HostIP}:$Port for task $($Task.Substring(0, 2))"
            }
            $client.EndConnect($connect)
        } finally {
            $connect.AsyncWaitHandle.Close()
        }

        $client.ReceiveTimeout = $TimeoutMs
        $client.SendTimeout = $TimeoutMs
        $stream = $client.GetStream()
        $request = [Text.Encoding]::UTF8.GetBytes("$Task`r`n")
        $stream.Write($request, 0, $request.Length)

        $buffer = New-Object byte[] 8192
        $response = [IO.MemoryStream]::new()
        try {
            $sawNewline = $false
            while ($response.Length -lt 8MB) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $newline = [Array]::IndexOf($buffer, [byte]10, 0, $read)
                $bytesToKeep = if ($newline -ge 0) { $newline + 1 } else { $read }
                $response.Write($buffer, 0, $bytesToKeep)
                if ($newline -ge 0) {
                    $sawNewline = $true
                    break
                }
            }
            if (-not $sawNewline) {
                throw "Task $($Task.Substring(0, 2)) returned an incomplete response ($($response.Length) bytes)"
            }
            $raw = [Text.Encoding]::UTF8.GetString($response.ToArray()).Trim()
            if (-not $raw) { throw "Task $($Task.Substring(0, 2)) returned no response" }
            return $raw
        } finally {
            $response.Dispose()
        }
    } finally {
        $client.Dispose()
    }
}

function ConvertTo-TLinkUIBody {
    param([Parameter(Mandatory = $true)][hashtable]$Value)
    $json = $Value | ConvertTo-Json -Compress -Depth 12
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
}

function ConvertFrom-TLinkUIResponse {
    param([Parameter(Mandatory = $true)][string]$Raw, [Parameter(Mandatory = $true)][int]$TaskType)
    if (-not $Raw.StartsWith("0;;")) { throw "Task $TaskType failed: $Raw" }
    $encoded = $Raw.Substring(3).Trim()
    if (-not $encoded) { throw "Task $TaskType returned an empty JSON payload" }
    try {
        $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
        return $json | ConvertFrom-Json
    } catch {
        throw "Task $TaskType returned invalid base64 JSON: $($_.Exception.Message)"
    }
}

function Assert-UIContext {
    param([Parameter(Mandatory = $true)]$Result, [Parameter(Mandatory = $true)][string]$Label)
    if ($Result.runtime -ne "rootfull") {
        throw "$Label reported runtime '$($Result.runtime)', expected the shared jailbreak runtime 'rootfull'"
    }
    if (-not $Result.bundle_id -or [int]$Result.pid -le 0) {
        throw "$Label did not report a valid foreground bundle/PID"
    }
    if ($Result.context_changed) { throw "$Label reports ui_context_changed" }
    if ($ExpectedBundle -and $Result.bundle_id -ne $ExpectedBundle) {
        throw "$Label foreground bundle '$($Result.bundle_id)' differs from '$ExpectedBundle'"
    }
}

$hasSelector = [bool]($Text -or $Identifier -or $Role)
$hasX = $PSBoundParameters.ContainsKey("AtX")
$hasY = $PSBoundParameters.ContainsKey("AtY")
if ($hasX -ne $hasY) { throw "Supply both -AtX and -AtY for task 80" }
if ($RequireMatch -and -not $hasSelector) { throw "-RequireMatch needs -Text, -Identifier, or -Role" }
if ($RequireHit -and -not $hasX) { throw "-RequireHit needs -AtX and -AtY" }
if ($Tap -and (-not $hasSelector -or -not $ExpectedBundle)) {
    throw "-Tap requires a selector and -ExpectedBundle to identify the target app"
}

$capability = ConvertFrom-TLinkUIResponse -TaskType 77 -Raw (Invoke-TLinkUITask -Task "77")
if ($capability.runtime -ne "rootfull" -or $capability.service -ne "springboard_script_bridge") {
    throw "Task 77 reached '$($capability.runtime)/$($capability.service)', expected rootfull/springboard_script_bridge; reinstall the package with SpringBoard UI tree routing"
}
if ($capability.schema -ne "ui_tree_capability_v1" -or $capability.source -ne "axruntime_numeric_v1") {
    throw "Task 77 capability schema/backend mismatch: $($capability.schema)/$($capability.source)"
}
if (-not $capability.ok -or $capability.state -ne "ready") {
    throw "UI Tree unavailable: state=$($capability.state), AX framework=$($capability.framework_loaded)"
}
foreach ($taskType in @(77, 78, 79, 80, 81)) {
    if (@($capability.tasks) -notcontains $taskType) {
        throw "Task 77 does not advertise UI task $taskType"
    }
}

$samples = @()
$snapshot = $null
$snapshotRequest = @{
    maxElements = $MaxElements
    timeoutMs = [Math]::Min($TimeoutMs, 3000)
    visibleOnly = $true
}
for ($index = 1; $index -le $RepeatCount; $index++) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $snapshot = ConvertFrom-TLinkUIResponse -TaskType 78 -Raw (
            Invoke-TLinkUITask -Task ("78" + (ConvertTo-TLinkUIBody -Value $snapshotRequest))
        )
    } catch {
        $probe = $capability.foreground_probe
        if ($null -eq $probe) {
            throw "Snapshot $index failed: $($_.Exception.Message). Task 77 has no foreground_probe; install a build containing the direct foreground resolver."
        }
        throw "Snapshot $index failed: $($_.Exception.Message). Task 77 foreground probe: source=$($probe.source) bundle=$($probe.bundle_id) pid=$($probe.pid) error=$($probe.error) direct_error=$($probe.direct_error) diagnostic=$($probe.diagnostic)"
    }
    $timer.Stop()
    if ($snapshot.schema -ne "ui_snapshot_v1" -or $snapshot.source -ne "axruntime_numeric_v1") {
        throw "Snapshot $index schema/backend mismatch: $($snapshot.schema)/$($snapshot.source)"
    }
    Assert-UIContext -Result $snapshot -Label "Snapshot $index"
    if ([int]$snapshot.count -lt $MinElements) {
        throw "Snapshot $index has $($snapshot.count) elements, expected at least $MinElements"
    }
    if ($RequireComplete -and [bool]$snapshot.partial) {
        throw "Snapshot $index is partial (truncated=$($snapshot.truncated))"
    }
    $samples += [pscustomobject]@{
        index = $index
        bundle_id = [string]$snapshot.bundle_id
        pid = [int]$snapshot.pid
        element_count = [int]$snapshot.count
        source_count = [int]$snapshot.source_count
        native_duration_ms = [double]$snapshot.duration_ms
        round_trip_ms = [Math]::Round($timer.Elapsed.TotalMilliseconds, 1)
        partial = [bool]$snapshot.partial
        truncated = [bool]$snapshot.truncated
    }
    if ($index -lt $RepeatCount -and $IntervalMs -gt 0) {
        Start-Sleep -Milliseconds $IntervalMs
    }
}

$selectorResult = $null
$tapResult = $null
if ($hasSelector) {
    $selector = @{ match = $Match; visibleOnly = $true }
    if ($Text) { $selector.text = $Text }
    if ($Identifier) { $selector.identifier = $Identifier }
    if ($Role) { $selector.role = $Role }
    $selectorResult = ConvertFrom-TLinkUIResponse -TaskType 79 -Raw (
        Invoke-TLinkUITask -Task ("79" + (ConvertTo-TLinkUIBody -Value $selector))
    )
    if ($selectorResult.schema -ne "ui_find_v1") { throw "Task 79 returned '$($selectorResult.schema)'" }
    Assert-UIContext -Result $selectorResult -Label "Find"
    if ($RequireMatch -and -not $selectorResult.found) { throw "Task 79 did not find the requested element" }

}

$hitResult = $null
if ($hasX) {
    $hitResult = ConvertFrom-TLinkUIResponse -TaskType 80 -Raw (
        Invoke-TLinkUITask -Task ("80" + (ConvertTo-TLinkUIBody -Value @{
            x = $AtX.Value
            y = $AtY.Value
        }))
    )
    if ($hitResult.schema -ne "ui_hit_test_v1") { throw "Task 80 returned '$($hitResult.schema)'" }
    Assert-UIContext -Result $hitResult -Label "Hit test"
    if ($RequireHit -and -not $hitResult.found) { throw "Task 80 returned no element at ($AtX, $AtY)" }
}

if ($Tap) {
    if ([int]$selectorResult.match_count -ne 1 -or -not $selectorResult.found) {
        throw "Tap requires exactly one selector match; task 79 found $($selectorResult.match_count)"
    }
    if (-not $selectorResult.element.enabled -or
        -not $selectorResult.element.clickable -or
        -not $selectorResult.element.activation_point_valid) {
        throw "The unique selector match is not enabled, clickable, and ready for tap"
    }
    $selector.clickableOnly = $true
    $tapResult = ConvertFrom-TLinkUIResponse -TaskType 81 -Raw (
        Invoke-TLinkUITask -Task ("81" + (ConvertTo-TLinkUIBody -Value $selector))
    )
    if ($tapResult.schema -ne "ui_tap_v1" -or -not $tapResult.tapped) {
        throw "Task 81 did not confirm a tap"
    }
    Assert-UIContext -Result $tapResult -Label "Tap"
}

$nativeTimes = @($samples | ForEach-Object { [double]$_.native_duration_ms } | Sort-Object)
$roundTripTimes = @($samples | ForEach-Object { [double]$_.round_trip_ms } | Sort-Object)
$p95Index = [Math]::Max(0, [int][Math]::Ceiling($RepeatCount * 0.95) - 1)
$result = [pscustomobject]@{
    host = $HostIP
    port = $Port
    requested_package_runtime = $Runtime
    reported_runtime = $capability.runtime
    service = $capability.service
    package_runtime_verified = $false
    capability_state = $capability.state
    backend = $capability.source
    entitlement_inspection = $capability.entitlements.'com.apple.private.accessibility.inspection'
    entitlement_api = $capability.entitlements.'com.apple.accessibility.api'
    hit_test_symbol = $capability.hit_test_symbol
    foreground_probe_source = $capability.foreground_probe.source
    foreground_probe_error = $capability.foreground_probe.error
    foreground_probe_direct_error = $capability.foreground_probe.direct_error
    foreground_probe_diagnostic = $capability.foreground_probe.diagnostic
    snapshot_schema = $snapshot.schema
    foreground_bundle = $snapshot.bundle_id
    foreground_pid = $snapshot.pid
    samples = $RepeatCount
    element_count = $snapshot.count
    partial_samples = @($samples | Where-Object { $_.partial }).Count
    native_average_ms = [Math]::Round(($nativeTimes | Measure-Object -Average).Average, 1)
    native_p95_ms = $nativeTimes[$p95Index]
    round_trip_average_ms = [Math]::Round(($roundTripTimes | Measure-Object -Average).Average, 1)
    round_trip_p95_ms = $roundTripTimes[$p95Index]
    selector_found = if ($selectorResult) { [bool]$selectorResult.found } else { "not_requested" }
    selector_matches = if ($selectorResult) { [int]$selectorResult.match_count } else { "not_requested" }
    hit_test_found = if ($hitResult) { [bool]$hitResult.found } else { "not_requested" }
    tapped = if ($tapResult) { [bool]$tapResult.tapped } else { "not_requested" }
    decision = if ($tapResult) {
        "pass_ui_tree_tap"
    } elseif (@($samples | Where-Object { $_.partial }).Count -gt 0) {
        "pass_partial_snapshot"
    } else {
        "pass_ui_tree_read_only"
    }
}
$result | Format-List | Out-Host
if ($RepeatCount -gt 1) {
    $samples | Format-Table index, bundle_id, pid, element_count, native_duration_ms, round_trip_ms, partial -AutoSize | Out-Host
}
