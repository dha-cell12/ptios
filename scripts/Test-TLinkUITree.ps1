param(
    [Parameter(Mandatory = $true)][string]$HostIP,
    [int]$Port = 6000,
    [int]$TimeoutMs = 10000,
    [ValidateRange(1, 1000)][int]$MaxElements = 250,
    [string]$Text = "",
    [string]$Identifier = "",
    [string]$Role = "",
    [ValidateSet("contains", "exact", "prefix")][string]$Match = "contains",
    [switch]$Tap
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkUITask([string]$Task) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = $TimeoutMs
        $client.SendTimeout = 5000
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $request = [Text.Encoding]::UTF8.GetBytes("$Task`r`n")
        $stream.Write($request, 0, $request.Length)
        $buffer = New-Object byte[] 8192
        $response = [IO.MemoryStream]::new()
        try {
            while ($response.Length -lt 4MB) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $response.Write($buffer, 0, $read)
                if ([Array]::IndexOf($buffer, [byte]10, 0, $read) -ge 0) { break }
            }
            return [Text.Encoding]::UTF8.GetString($response.ToArray()).Trim()
        } finally { $response.Dispose() }
    } finally { $client.Dispose() }
}

function ConvertTo-TLinkUIBody([hashtable]$Value) {
    $json = $Value | ConvertTo-Json -Compress -Depth 12
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
}

function ConvertFrom-TLinkUIResponse([string]$Raw) {
    if ($Raw -notlike "0;;*") { throw "TLink UI task failed: $Raw" }
    $encoded = ($Raw -split ";;", 2)[1]
    $json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
    return $json | ConvertFrom-Json
}

$capability = ConvertFrom-TLinkUIResponse (Invoke-TLinkUITask "77")
$snapshotRequest = @{ maxElements = $MaxElements; timeoutMs = [Math]::Min($TimeoutMs, 3000); visibleOnly = $true }
$snapshotRaw = Invoke-TLinkUITask ("78" + (ConvertTo-TLinkUIBody $snapshotRequest))
if ($snapshotRaw -notlike "0;;*") {
    [pscustomobject]@{
        host = $HostIP
        runtime = $capability.runtime
        service = $capability.service
        capability_state = $capability.state
        foreground_ok = $capability.foreground_context.ok
        foreground_bundle = $capability.foreground_context.bundle_id
        foreground_pid = $capability.foreground_context.pid
        foreground_source = $capability.foreground_context.source
        foreground_error = $capability.foreground_context.error
        foreground_diagnostic = $capability.foreground_context.diagnostic
        foreground_fallback_error = $capability.foreground_context.fallback_error
        snapshot_error = $snapshotRaw
        decision = "fail_foreground_discovery"
    } | Format-List | Out-Host
    throw "TLink UI snapshot failed: $snapshotRaw"
}
$snapshot = ConvertFrom-TLinkUIResponse $snapshotRaw

$selectorResult = $null
$tapResult = $null
if ($Text -or $Identifier -or $Role) {
    $selector = @{ match = $Match; visibleOnly = $true }
    if ($Text) { $selector.text = $Text }
    if ($Identifier) { $selector.identifier = $Identifier }
    if ($Role) { $selector.role = $Role }
    $selectorResult = ConvertFrom-TLinkUIResponse (Invoke-TLinkUITask ("79" + (ConvertTo-TLinkUIBody $selector)))
    if ($Tap) {
        $selector.clickableOnly = $true
        $tapResult = ConvertFrom-TLinkUIResponse (Invoke-TLinkUITask ("81" + (ConvertTo-TLinkUIBody $selector)))
    }
} elseif ($Tap) {
    throw "-Tap requires -Text, -Identifier, or -Role"
}

[pscustomobject]@{
    host = $HostIP
    runtime = $capability.runtime
    service = $capability.service
    state = $capability.state
    backend = $capability.source
    entitlement_inspection = $capability.entitlements.'com.apple.private.accessibility.inspection'
    entitlement_api = $capability.entitlements.'com.apple.accessibility.api'
    snapshot_schema = $snapshot.schema
    foreground_bundle = $snapshot.bundle_id
    foreground_pid = $snapshot.pid
    element_count = $snapshot.count
    source_count = $snapshot.source_count
    duration_ms = $snapshot.duration_ms
    partial = $snapshot.partial
    truncated = $snapshot.truncated
    selector_found = if ($selectorResult) { $selectorResult.found } else { "not_requested" }
    selector_matches = if ($selectorResult) { $selectorResult.match_count } else { "not_requested" }
    tapped = if ($tapResult) { $tapResult.tapped } else { "not_requested" }
    decision = if ($capability.state -eq "ready" -and -not $snapshot.context_changed) { "pass_ui_tree_read_only" } else { "fail_ui_tree" }
} | Format-List
