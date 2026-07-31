param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [switch]$ExpectReady,
    [switch]$RunTransitions
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

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected) {
        throw "$Label expected '$Expected', got '$Actual'"
    }
}

$capability = Invoke-TLinkVPNTask -Task "97"
if ($capability -notlike "0;;*" -or
    $capability -notlike "*vpnPhase=3*" -or
    $capability -notlike "*vpnState=foreground_candidate*") {
    throw "Task 97 does not report VPN P3 foreground candidate: $capability"
}

$raw = Invoke-TLinkVPNTask -Task "592"
if ($raw -notlike "0;;*") { throw "Task 592 failed: $raw" }
$base64 = ($raw -split ";;", 2)[1]
$diagnostics = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($base64)
) | ConvertFrom-Json

Assert-Equal $diagnostics.phase 3 "diagnostics phase"
Assert-Equal $diagnostics.runtime "trollstore" "diagnostics runtime"
Assert-Equal $diagnostics.profile_identifier "tlinkauto-managed-v1" "profile identifier"

if ($ExpectReady) {
    Assert-Equal $diagnostics.entitlement_probe_scope "foreground_app_process" "probe scope"
    Assert-Equal ([bool]$diagnostics.app_active) $true "foreground app"
    Assert-Equal ([bool]$diagnostics.entitlements.allow_vpn) $true "allow-vpn entitlement"
    Assert-Equal ([bool]$diagnostics.broker_ready) $true "broker ready"
    Assert-Equal $diagnostics.control_preflight "foreground_manager_ready" "control preflight"
    Assert-Equal $diagnostics.profile_state "configured" "profile state"
}

if ($RunTransitions) {
    if (-not $ExpectReady) {
        throw "-RunTransitions requires -ExpectReady and a configured real IKEv2 profile"
    }
    Assert-Equal (Invoke-TLinkVPNTask -Task "591;;1") "0;;1" "connect"
    Assert-Equal (Invoke-TLinkVPNTask -Task "590") "0;;1" "connected query"
    Assert-Equal (Invoke-TLinkVPNTask -Task "591;;0") "0;;0" "disconnect"
    Assert-Equal (Invoke-TLinkVPNTask -Task "590") "0;;0" "disconnected query"
}

[pscustomobject]@{
    host = $HostIP
    phase = $diagnostics.phase
    app_active = $diagnostics.app_active
    allow_vpn = $diagnostics.entitlements.allow_vpn
    broker_ready = $diagnostics.broker_ready
    profile_state = $diagnostics.profile_state
    connection_status = $diagnostics.manager_status.connection_status
    transitions_run = [bool]$RunTransitions
} | Format-List
