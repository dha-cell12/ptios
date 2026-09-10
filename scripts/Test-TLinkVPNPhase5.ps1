param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [switch]$RequireManagedProfile,
    [switch]$RequirePrivateProfile,
    [ValidateSet("PPTP", "L2TP", "IPSec")]
    [string]$ExpectedPrivateType,
    [switch]$RunConnect,
    [switch]$RunDisconnect
)

$ErrorActionPreference = "Stop"

if ($RequireManagedProfile -and $RequirePrivateProfile) {
    throw "Choose either -RequireManagedProfile (IKEv2) or -RequirePrivateProfile (PPTP/L2TP/IPSec), not both."
}
if ($ExpectedPrivateType -and -not $RequirePrivateProfile) {
    throw "-ExpectedPrivateType requires -RequirePrivateProfile."
}

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
    $capability -notlike "*vpnBackgroundAgent=candidate_mobile_process_v9_super_configuration*" -or
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
Assert-Equal ([bool]$diagnostics.entitlements.scpreferences_write_access) $true "SCPreferences write entitlement"
Assert-Equal ([bool]$diagnostics.entitlements.scdynamicstore_write_access) $true "SCDynamicStore write entitlement"
Assert-Equal ([bool]$diagnostics.entitlements.profiled_access) $true "profiled access entitlement"
Assert-Equal ([bool]$diagnostics.entitlements.mdmd_access) $true "mdmd access entitlement"
Assert-Equal ([bool]$diagnostics.entitlements.user_preference_read) $true "user-preference-read entitlement"
Assert-Equal ([bool]$diagnostics.entitlements.user_preference_write) $true "user-preference-write entitlement"
Assert-Equal ([bool]$diagnostics.entitlements.private_configuration_super) $true "private NetworkExtension configuration entitlement"
Assert-Equal ([bool]$diagnostics.entitlements.managed_vpn_keychain_access) $true "managed VPN Keychain access group"
Assert-Equal $diagnostics.agent_version 9 "vpnagent version"
Assert-Equal $diagnostics.process_uid 501 "vpnagent uid"
Assert-Equal $diagnostics.process_euid 501 "vpnagent euid"
Assert-Equal $diagnostics.process_gid 501 "vpnagent gid"
Assert-Equal $diagnostics.process_egid 501 "vpnagent egid"
Assert-Equal ([bool]$diagnostics.private_compatibility.candidate_ready) $true "private VPN candidate"

$requireProfile = [bool]($RequireManagedProfile -or $RequirePrivateProfile)
if ($RequireManagedProfile) {
    Assert-Equal ([bool]$diagnostics.manager_status.configured) $true "IKEv2 profile configured"
    Assert-Equal $diagnostics.manager_status.backend "nevpnmanager_ikev2" "managed profile backend"
    Assert-Equal $diagnostics.manager_status.profile_type "IKEv2" "managed profile type"
    Assert-Equal $diagnostics.manager_status.approval_path "nevpnmanager_public" "managed approval path"
}
if ($RequirePrivateProfile) {
    Assert-Equal ([bool]$diagnostics.manager_status.configured) $true "private legacy profile configured"
    Assert-Equal $diagnostics.manager_status.backend "vpnconnectionstore_private" "private profile backend"
    Assert-Equal $diagnostics.manager_status.approval_path "privhelper_root_private_store_no_nevpnmanager" "private approval path"
    Assert-Equal ([bool]$diagnostics.private_compatibility.mutating_api_exercised) $true "private marker mutation evidence"
    if ($ExpectedPrivateType) {
        Assert-Equal $diagnostics.manager_status.profile_type $ExpectedPrivateType "private profile type"
    }
}

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
    private_bundle_loaded = $diagnostics.private_compatibility.bundle_loaded
    private_store_available = $diagnostics.private_compatibility.shared_store_available
    private_create_selector = $diagnostics.private_compatibility.create_profile_selector
    private_select_selector = $diagnostics.private_compatibility.select_profile_selector
    private_connection_selector = $diagnostics.private_compatibility.connection_selector
    private_candidate_ready = $diagnostics.private_compatibility.candidate_ready
    scpreferences_write_access = $diagnostics.entitlements.scpreferences_write_access
    scdynamicstore_write_access = $diagnostics.entitlements.scdynamicstore_write_access
    profiled_access = $diagnostics.entitlements.profiled_access
    mdmd_access = $diagnostics.entitlements.mdmd_access
    user_preference_read = $diagnostics.entitlements.user_preference_read
    user_preference_write = $diagnostics.entitlements.user_preference_write
    private_configuration_super = $diagnostics.entitlements.private_configuration_super
    managed_vpn_keychain_access = $diagnostics.entitlements.managed_vpn_keychain_access
    private_mutating_api_exercised = $diagnostics.private_compatibility.mutating_api_exercised
    private_load_error = $diagnostics.private_compatibility.load_error
    manager_backend = $diagnostics.manager_status.backend
    profile_type = $diagnostics.manager_status.profile_type
    approval_path = $diagnostics.manager_status.approval_path
    profile_identifier = $diagnostics.manager_status.profile_identifier
    managed_profile_required = [bool]$RequireManagedProfile
    private_profile_required = [bool]$RequirePrivateProfile
    connect_test_run = [bool]$RunConnect
    disconnect_test_run = [bool]$RunDisconnect
} | Format-List
