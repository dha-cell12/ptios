[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Domain,

    [Parameter(Mandatory = $true)]
    [string]$Token,

    [int]$ExpectedDevices = -1
)

$ErrorActionPreference = "Stop"

if ($Token.Length -lt 16) {
    throw "Token must contain at least 16 characters."
}

$base = $Domain.Trim().TrimEnd("/")
if ($base.StartsWith("wss://", [StringComparison]::OrdinalIgnoreCase)) {
    $base = "https://" + $base.Substring(6)
} elseif ($base.StartsWith("ws://", [StringComparison]::OrdinalIgnoreCase)) {
    $base = "http://" + $base.Substring(5)
}
if (-not ($base.StartsWith("https://", [StringComparison]::OrdinalIgnoreCase) -or
          $base.StartsWith("http://", [StringComparison]::OrdinalIgnoreCase))) {
    throw "Domain must start with https://, http://, wss://, or ws://."
}

$headers = @{ Authorization = "Bearer $Token" }
$status = Invoke-RestMethod -Method Get -Uri "$base/remote/device/status" -Headers $headers
$devices = @(Invoke-RestMethod -Method Get -Uri "$base/devices")
$remoteDevices = @($devices | Where-Object {
    $_.platform -eq "ios" -and
    ($_.id -like "ios-remote:*" -or $_.meta.transport -eq "remote_wss")
})

if (-not $status.enabled) {
    throw "Remote iOS is disabled in bridge-rs. Restart the bridge with TLINK_REMOTE_TOKEN set."
}
if ($status.protocol -ne "tlink-remote-wss-v1") {
    throw "Unexpected protocol: $($status.protocol)"
}
if ($status.connected_devices -ne $remoteDevices.Count) {
    throw "Status/device registry mismatch: status=$($status.connected_devices), registry=$($remoteDevices.Count)"
}
if ($ExpectedDevices -ge 0 -and $remoteDevices.Count -ne $ExpectedDevices) {
    throw "Expected $ExpectedDevices remote device(s), found $($remoteDevices.Count)."
}

[pscustomobject]@{
    passed = $true
    endpoint = $base
    protocol = $status.protocol
    connected_devices = $status.connected_devices
    remote_devices = @($remoteDevices | ForEach-Object {
        [pscustomobject]@{
            id = $_.id
            name = $_.display_name
            transport = $_.meta.transport
            capabilities = @($_.capabilities)
        }
    })
} | ConvertTo-Json -Depth 8

