param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [switch]$RunConnect,
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
        finally { $response.Dispose() }
    }
    finally { $client.Dispose() }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected) { throw "$Label expected '$Expected', got '$Actual'" }
}

function Get-TLinkVPNDiagnostics {
    $raw = Invoke-TLinkVPNTask -Task "592"
    if ($raw -notlike "0;;*") { throw "Task 592 failed: $raw" }
    return [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String(($raw -split ";;", 2)[1])
    ) | ConvertFrom-Json
}

$capability = Invoke-TLinkVPNTask -Task "97"
if ($capability -notlike "0;;*" -or
    $capability -notlike "*vpnPhase=5*" -or
    $capability -notlike "*vpnState=background_control*" -or
    $capability -notlike "*vpnBroker=vpnagent_6016_then_StreamControl_6015*") {
    throw "Task 97 does not report TrollStore VPN P5: $capability"
}

$diagnostics = Get-TLinkVPNDiagnostics
$initialConnectionStatus = $diagnostics.manager_status.connection_status

Assert-Equal $diagnostics.phase 5 "diagnostics phase"
Assert-Equal $diagnostics.runtime "trollstore" "runtime"
Assert-Equal $diagnostics.state "background_control" "state"
Assert-Equal $diagnostics.diagnostics_source "background_vpnagent" "diagnostics source"
Assert-Equal ([bool]$diagnostics.broker_ready) $true "background agent readiness"
Assert-Equal ([bool]$diagnostics.entitlements.allow_vpn) $true "allow-vpn entitlement"
Assert-Equal $diagnostics.agent_version 2 "vpnagent version"
Assert-Equal $diagnostics.process_uid 501 "vpnagent uid"
Assert-Equal $diagnostics.process_euid 501 "vpnagent euid"
Assert-Equal $diagnostics.process_gid 501 "vpnagent gid"
Assert-Equal $diagnostics.process_egid 501 "vpnagent egid"

$query = Invoke-TLinkVPNTask -Task "590"
if ($query -notin @("0;;0", "0;;1")) { throw "VPN query failed: $query" }

if ($RunConnect) {
    Assert-Equal (Invoke-TLinkVPNTask -Task "591;;1") "0;;1" "background connect"
    Assert-Equal (Invoke-TLinkVPNTask -Task "590") "0;;1" "connected query"
}
if ($RunDisconnect) {
    Assert-Equal (Invoke-TLinkVPNTask -Task "591;;0") "0;;0" "background disconnect"
    Assert-Equal (Invoke-TLinkVPNTask -Task "590") "0;;0" "disconnected query"
}

if ($RunConnect -or $RunDisconnect) {
    $diagnostics = Get-TLinkVPNDiagnostics
}

[pscustomobject]@{
    host = $HostIP
    runtime = $diagnostics.runtime
    phase = $diagnostics.phase
    state = $diagnostics.state
    diagnostics_source = $diagnostics.diagnostics_source
    broker_ready = $diagnostics.broker_ready
    agent_version = $diagnostics.agent_version
    process_uid = $diagnostics.process_uid
    process_gid = $diagnostics.process_gid
    initial_connection_status = $initialConnectionStatus
    connection_status = $diagnostics.manager_status.connection_status
    connect_test_run = [bool]$RunConnect
    disconnect_test_run = [bool]$RunDisconnect
} | Format-List
