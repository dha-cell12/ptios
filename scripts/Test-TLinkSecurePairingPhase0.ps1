param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [Parameter(Mandatory = $true)]
    [ValidateSet("rootfull", "trollstore")]
    [string]$Runtime,
    [int]$Port = 6000
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkPairingBaselineTask {
    param([Parameter(Mandatory = $true)][string]$Task)

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = 10000
        $client.SendTimeout = 5000
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $request = [Text.Encoding]::ASCII.GetBytes("$Task`r`n")
        $stream.Write($request, 0, $request.Length)
        $buffer = New-Object byte[] 8192
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

$capability = Invoke-TLinkPairingBaselineTask -Task "97"
if ($capability -notlike "0;;*") { throw "Task 97 failed: $capability" }

$required = @(
    "runtime=$Runtime",
    "securePairingState=contract_only",
    "securePairingPhase=0",
    "securePairingContractVersion=1",
    "securePairingTransport=zxsp_json_v1",
    "securePairingMode=observe_only",
    "securePairingLegacyPolicy=unchanged_p0",
    "securePairingCrypto=p256_ecdh_ecdsa_hkdf_sha256_aes256_gcm",
    "securePairingDeviceValidated=0"
)
foreach ($marker in $required) {
    if ($capability -notlike "*$marker*") {
        throw "Task 97 is missing '$marker': $capability"
    }
}

# P0 is read-only and must prove that the established plaintext health path was
# not changed. It deliberately sends no ZXSP frame and creates no pairing state.
$health = Invoke-TLinkPairingBaselineTask -Task "99"
if ($health -notlike "0;;*") { throw "Legacy health task changed: $health" }

[pscustomobject]@{
    host = $HostIP
    runtime = $Runtime
    phase = 0
    state = "contract_only"
    enforcement = "observe_only"
    legacy_health = "passed"
    pairing_attempted = $false
    device_validated = $false
} | Format-List
