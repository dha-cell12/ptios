param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [ValidateSet("rootfull", "trollstore")]
    [string]$Runtime,
    [int]$Port = 6000,
    [switch]$ExpectOnDemand,
    [switch]$RunDisconnect
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkVPNTask {
    param([Parameter(Mandatory = $true)][string]$Task)

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = 35000
        $client.SendTimeout = 5000
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $request = [Text.Encoding]::ASCII.GetBytes("$Task`r`n")
        $stream.Write($request, 0, $request.Length)
        $buffer = New-Object byte[] 4096
        $response = [IO.MemoryStream]::new()
        try {
            while ($response.Length -lt 262144) {
                $read = $stream.Read($buffer, 0, $buffer.Length)
                if ($read -le 0) { break }
                $response.Write($buffer, 0, $read)
                if ([Array]::IndexOf($buffer, [byte]10, 0, $read) -ge 0) { break }
            }
            return [Text.Encoding]::UTF8.GetString($response.ToArray()).Trim()
        }
        finally {
            $response.Dispose()
        }
    }
    finally {
        $client.Dispose()
    }
}

function Get-TLinkVPNDiagnostics {
    $raw = Invoke-TLinkVPNTask -Task "592"
    if ($raw -notlike "0;;*") { throw "Task 592 failed: $raw" }
    $base64 = ($raw -split ";;", 2)[1]
    return [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($base64)
    ) | ConvertFrom-Json
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected) {
        throw "$Label expected '$Expected', got '$Actual'"
    }
}

$expectedState = if ($Runtime -eq "rootfull") {
    "full_control"
}
else {
    "app_side_control"
}
$capability = Invoke-TLinkVPNTask -Task "97"
if ($capability -notlike "0;;*" -or
    $capability -notlike "*vpnPhase=4*" -or
    $capability -notlike "*vpnState=$expectedState*" -or
    $capability -notlike "*vpnOnDemand=local_ui_connect_all_networks*" -or
    $capability -notlike "*vpnDisconnectPolicy=explicit_disconnect_disables_on_demand*") {
    throw "Task 97 does not report VPN P4 for $Runtime`: $capability"
}

$diagnostics = Get-TLinkVPNDiagnostics
Assert-Equal $diagnostics.phase 4 "diagnostics phase"
Assert-Equal $diagnostics.runtime $Runtime "diagnostics runtime"
Assert-Equal $diagnostics.state $expectedState "diagnostics state"
Assert-Equal $diagnostics.profile_identifier "tlinkauto-managed-v1" "profile identifier"
Assert-Equal $diagnostics.on_demand_policy `
    "local_ui_connect_all_networks_explicit_disconnect_disables" `
    "on-demand policy"

if ($ExpectOnDemand) {
    $hasManagerStatus = $null -ne $diagnostics.manager_status
    $isForegroundBroker =
        $diagnostics.diagnostics_source -eq "foreground_app_broker" -or
        ([string]::IsNullOrEmpty($diagnostics.diagnostics_source) -and
         $hasManagerStatus -and [bool]$diagnostics.broker_ready)
    if ($Runtime -eq "trollstore" -and -not $isForegroundBroker) {
        $brokerError = if ($diagnostics.broker_last_error) {
            $diagnostics.broker_last_error
        }
        else {
            "unknown"
        }
        throw "Task 592 used streamd fallback instead of foreground broker; " +
            "broker_last_error=$brokerError foreground_heartbeat_fresh=" +
            "$($diagnostics.foreground_heartbeat_fresh). Keep StreamControl active " +
            "and install a build containing the VPN P4 diagnostics retry fix."
    }
    if (-not $hasManagerStatus) {
        throw "Task 592 did not return manager_status; diagnostics_source=" +
            "$($diagnostics.diagnostics_source)"
    }
    if (-not [bool]$diagnostics.manager_status.on_demand_enabled) {
        throw "Authoritative VPN manager reports on-demand disabled; " +
            "diagnostics_source=$($diagnostics.diagnostics_source) " +
            "connection_status=$($diagnostics.manager_status.connection_status) " +
            "rule_count=$($diagnostics.manager_status.on_demand_rule_count) " +
            "mode=$($diagnostics.manager_status.on_demand_mode). An immediate VPN " +
            "connection alone does not prove that iOS persisted auto-reconnect."
    }
    if ([int]$diagnostics.manager_status.on_demand_rule_count -lt 1) {
        throw "on-demand rule count must be at least 1"
    }
    Assert-Equal $diagnostics.manager_status.on_demand_mode `
        "connect_all_networks" `
        "on-demand mode"
}

if ($RunDisconnect) {
    if (-not $ExpectOnDemand) {
        throw "-RunDisconnect requires -ExpectOnDemand after enabling Auto-Reconnect in local UI"
    }
    Assert-Equal (Invoke-TLinkVPNTask -Task "591;;0") "0;;0" "disconnect"
    Assert-Equal (Invoke-TLinkVPNTask -Task "590") "0;;0" "disconnected query"
    $after = Get-TLinkVPNDiagnostics
    Assert-Equal ([bool]$after.manager_status.on_demand_enabled) $false `
        "explicit disconnect disables on-demand"
    Assert-Equal ([int]$after.manager_status.on_demand_rule_count) 0 `
        "explicit disconnect clears on-demand rules"
}

[pscustomobject]@{
    host = $HostIP
    runtime = $Runtime
    phase = $diagnostics.phase
    state = $diagnostics.state
    connection_status = $diagnostics.manager_status.connection_status
    on_demand_enabled = $diagnostics.manager_status.on_demand_enabled
    on_demand_rule_count = $diagnostics.manager_status.on_demand_rule_count
    disconnect_test_run = [bool]$RunDisconnect
} | Format-List
