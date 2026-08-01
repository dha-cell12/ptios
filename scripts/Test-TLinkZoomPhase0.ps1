param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [Parameter(Mandatory = $true)]
    [ValidateSet("rootfull", "trollstore")]
    [string]$Runtime,
    [int]$Port = 6000
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkZoomTask {
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
        finally {
            $response.Dispose()
        }
    }
    finally {
        $client.Dispose()
    }
}

$capability = Invoke-TLinkZoomTask -Task "97"
$required = @(
    "runtime=$Runtime",
    "multiTouchRaw=legacy_task10_parent_frames",
    "zoomState=contract_only",
    "zoomTask=64",
    "zoomWire=task64_additive_zoom_v1",
    "zoomFingerCounts=2,3",
    "zoomBackend=legacy_multitouch_parent_frames",
    "zoomPhase=0"
)
if ($capability -notlike "0;;*") {
    throw "Task 97 failed: $capability"
}
foreach ($marker in $required) {
    if ($capability -notlike "*$marker*") {
        throw "Task 97 is missing '$marker': $capability"
    }
}

# P0 reserves and rejects the additive syntax. It deliberately sends no touch.
$probe = Invoke-TLinkZoomTask -Task "64zoom;;500;;900;;60;;160;;300;;2;;20"
if ($probe -ne "-1;;zoom_not_implemented_phase0") {
    throw "Reserved task 64 zoom probe expected '-1;;zoom_not_implemented_phase0', got '$probe'"
}

[pscustomobject]@{
    host = $HostIP
    runtime = $Runtime
    phase = 0
    state = "contract_only"
    raw_multi_touch_foundation = $true
    finger_counts_reserved = "2,3"
    legacy_task64_unchanged = $true
    gesture_dispatched = $false
} | Format-List
