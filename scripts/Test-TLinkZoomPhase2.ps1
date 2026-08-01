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
        finally { $response.Dispose() }
    }
    finally { $client.Dispose() }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected) { throw "$Label expected '$Expected', got '$Actual'" }
}

function Get-TLinkZoomDiagnostics {
    $raw = Invoke-TLinkZoomTask -Task "60"
    if ($raw -notlike "0;;*") { throw "Task 60 failed: $raw" }
    $base64 = ($raw -split ";;", 2)[1]
    $status = [Text.Encoding]::UTF8.GetString(
        [Convert]::FromBase64String($base64)
    ) | ConvertFrom-Json
    $diagnostics = if ($Runtime -eq "rootfull") {
        $status.zoom.diagnostics
    }
    else {
        $status.capabilities.zoomDiagnostics
    }
    if (-not $diagnostics) { throw "Task 60 is missing Zoom P2 diagnostics for $Runtime" }
    Assert-Equal $diagnostics.schema "zoom_runtime_diagnostics_v1" "diagnostics schema"
    return $diagnostics
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
    $response = Invoke-TLinkZoomTask -Task ($values -join ";;")
    Assert-Equal $response "0" $Label
}

$capability = Invoke-TLinkZoomTask -Task "97"
$required = @(
    "runtime=$Runtime",
    "zoomState=experimental",
    "zoomTask=64",
    "zoomWire=task64_additive_zoom_v1",
    "zoomPhase=2",
    "zoomDiagnostics=zoom_runtime_diagnostics_v1",
    "zoomClients=task64_python_js_webtango_v1",
    "zoomDeviceValidated=0"
)
if ($capability -notlike "0;;*") { throw "Task 97 failed: $capability" }
foreach ($marker in $required) {
    if ($capability -notlike "*$marker*") { throw "Task 97 is missing '$marker': $capability" }
}

$before = Get-TLinkZoomDiagnostics
$invalid = Invoke-TLinkZoomTask -Task "64zoom;;$CenterX;;$CenterY;;60;;160;;300;;4;;20"
Assert-Equal $invalid "-1;;zoom_finger_count_unsupported allowed=2,3" "safe validation probe"
$afterValidation = Get-TLinkZoomDiagnostics
Assert-Equal ([uint64]$afterValidation.attempt_count - [uint64]$before.attempt_count) 1 "validation attempt delta"
Assert-Equal ([uint64]$afterValidation.validation_rejected_count - [uint64]$before.validation_rejected_count) 1 "validation reject delta"
Assert-Equal ([uint64]$afterValidation.frame_count - [uint64]$before.frame_count) 0 "validation frame delta"
Assert-Equal $afterValidation.last_result "validation_rejected" "validation last result"
Assert-Equal ([uint64]$afterValidation.in_flight) 0 "validation in-flight"

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

$after = Get-TLinkZoomDiagnostics
if ($RunGesture) {
    $gestureCount = [uint64]$ran.Count
    Assert-Equal ([uint64]$after.success_count - [uint64]$afterValidation.success_count) $gestureCount "success delta"
    Assert-Equal ([uint64]$after.frame_count - [uint64]$afterValidation.frame_count) ($gestureCount * ($Steps + 1)) "gesture frame delta"
    Assert-Equal ([int]$after.last_finger_count) $FingerCount "last finger count"
    Assert-Equal ([int]$after.last_steps) $Steps "last steps"
    Assert-Equal ([int]$after.last_duration_ms) $DurationMs "last duration"
    Assert-Equal $after.last_direction $ran[-1] "last direction"
    Assert-Equal $after.last_result "success" "gesture last result"
    Assert-Equal ([uint64]$after.in_flight) 0 "gesture in-flight"
}

[pscustomobject]@{
    host = $HostIP
    runtime = $Runtime
    phase = 2
    state = "experimental"
    validation_probe = "passed_without_frames"
    gesture_test_run = [bool]$RunGesture
    directions_run = ($ran -join ",")
    attempts = $after.attempt_count
    successes = $after.success_count
    validation_rejected = $after.validation_rejected_count
    frames = $after.frame_count
    last_result = $after.last_result
    device_evidence_required = $true
} | Format-List
