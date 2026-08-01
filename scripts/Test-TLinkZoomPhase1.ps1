param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [Parameter(Mandatory = $true)]
    [ValidateSet("rootfull", "trollstore")]
    [string]$Runtime,
    [int]$Port = 6000,
    [switch]$RunGesture,
    [ValidateSet("spread", "pinch", "both")]
    [string]$Direction = "both",
    [double]$CenterX = 375,
    [double]$CenterY = 667,
    [double]$StartRadius = 60,
    [double]$EndRadius = 160,
    [ValidateSet(2, 3)]
    [int]$FingerCount = 2,
    [int]$DurationMs = 300,
    [int]$Steps = 20,
    [double]$AngleDegrees = 0,
    [int]$BaseFinger = 0
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkZoomTask {
    param([Parameter(Mandatory = $true)][string]$Task)

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = 15000
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

function Assert-TLinkZoomSuccess {
    param([string]$Response, [string]$Label)
    if ($Response -ne "0") {
        throw "$Label expected '0', got '$Response'"
    }
}

function Invoke-TLinkZoomGesture {
    param([double]$FromRadius, [double]$ToRadius, [string]$Label)
    $values = @(
        "64zoom",
        $CenterX.ToString([Globalization.CultureInfo]::InvariantCulture),
        $CenterY.ToString([Globalization.CultureInfo]::InvariantCulture),
        $FromRadius.ToString([Globalization.CultureInfo]::InvariantCulture),
        $ToRadius.ToString([Globalization.CultureInfo]::InvariantCulture),
        $DurationMs,
        $FingerCount,
        $Steps,
        $AngleDegrees.ToString([Globalization.CultureInfo]::InvariantCulture),
        $BaseFinger
    )
    Assert-TLinkZoomSuccess (Invoke-TLinkZoomTask -Task ($values -join ";;")) $Label
}

$capability = Invoke-TLinkZoomTask -Task "97"
$required = @(
    "runtime=$Runtime",
    "multiTouchRaw=legacy_task10_parent_frames",
    "zoomState=experimental",
    "zoomTask=64",
    "zoomWire=task64_additive_zoom_v1",
    "zoomFingerCounts=2,3",
    "zoomBackend=legacy_multitouch_parent_frames",
    "zoomPhase=1",
    "zoomGeometry=radial_linear_interpolation_v1",
    "zoomValidation=preflight_bounds_v1",
    "zoomCleanup=all_fingers_up_on_exception_v1",
    "zoomDeviceValidated=0"
)
if ($capability -notlike "0;;*") { throw "Task 97 failed: $capability" }
foreach ($marker in $required) {
    if ($capability -notlike "*$marker*") {
        throw "Task 97 is missing '$marker': $capability"
    }
}

# This rejection is preflight-only and must never dispatch a touch frame.
$invalid = Invoke-TLinkZoomTask -Task "64zoom;;$CenterX;;$CenterY;;60;;160;;300;;4;;20"
if ($invalid -ne "-1;;zoom_finger_count_unsupported allowed=2,3") {
    throw "Safe validation probe returned unexpected response: $invalid"
}

$ran = @()
if ($RunGesture) {
    if ($Direction -eq "spread" -or $Direction -eq "both") {
        Invoke-TLinkZoomGesture -FromRadius $StartRadius -ToRadius $EndRadius -Label "spread"
        $ran += "spread"
    }
    if ($Direction -eq "both") { Start-Sleep -Milliseconds 500 }
    if ($Direction -eq "pinch" -or $Direction -eq "both") {
        Invoke-TLinkZoomGesture -FromRadius $EndRadius -ToRadius $StartRadius -Label "pinch"
        $ran += "pinch"
    }
}

[pscustomobject]@{
    host = $HostIP
    runtime = $Runtime
    phase = 1
    state = "experimental"
    validation_probe = "passed_without_touch"
    gesture_test_run = [bool]$RunGesture
    directions_run = ($ran -join ",")
    finger_count = $FingerCount
    device_evidence_required = $true
} | Format-List
