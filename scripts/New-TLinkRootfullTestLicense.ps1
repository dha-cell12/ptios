[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Endpoint = "https://tlinkauto-license.tlinkauto.workers.dev",
    [SecureString]$AdminToken,
    [string]$LicenseKey = "",
    [ValidateRange(0, 3650)]
    [int]$ValidDays = 7,
    [ValidateRange(1, 1000)]
    [int]$MaxDevices = 1,
    [ValidateSet("automation", "stream", "script", "admin", "shell")]
    [string[]]$Features = @("automation", "stream", "script", "admin", "shell")
)

$ErrorActionPreference = "Stop"

if (-not $AdminToken -and $env:TLINK_LICENSE_ADMIN_TOKEN) {
    $AdminToken = ConvertTo-SecureString $env:TLINK_LICENSE_ADMIN_TOKEN -AsPlainText -Force
}
if (-not $AdminToken) {
    $AdminToken = Read-Host "Cloudflare Worker ADMIN_TOKEN" -AsSecureString
}

if ([string]::IsNullOrWhiteSpace($LicenseKey)) {
    $suffix = [Guid]::NewGuid().ToString("N").Substring(0, 12).ToUpperInvariant()
    $LicenseKey = "TLINK-ROOTFULL-TEST-$suffix"
}
$LicenseKey = $LicenseKey.Trim().ToUpperInvariant()

$endpointBase = $Endpoint.Trim().TrimEnd("/")
$uri = "$endpointBase/v1/admin/licenses"
$expiresAt = if ($ValidDays -eq 0) {
    0
} else {
    [DateTimeOffset]::UtcNow.AddDays($ValidDays).ToUnixTimeSeconds()
}

$body = [ordered]@{
    license_key = $LicenseKey
    max_devices = $MaxDevices
    expires_at = $expiresAt
    features = @($Features)
}

$tokenPointer = [IntPtr]::Zero
try {
    $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminToken)
    $plainAdminToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
    if ([string]::IsNullOrWhiteSpace($plainAdminToken)) {
        throw "ADMIN_TOKEN cannot be empty."
    }

    if (-not $PSCmdlet.ShouldProcess($uri, "Create rootfull test license $LicenseKey")) {
        return
    }

    try {
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri $uri `
            -Headers @{ Authorization = "Bearer $plainAdminToken" } `
            -ContentType "application/json" `
            -Body ($body | ConvertTo-Json -Depth 4 -Compress)
    }
    catch {
        $details = ""
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $details = " $($_.ErrorDetails.Message)"
        }
        throw "Could not create test license at $uri.$details"
    }
}
finally {
    $plainAdminToken = $null
    if ($tokenPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
    }
}

$expiryText = if ($response.expires_at -and [int64]$response.expires_at -gt 0) {
    [DateTimeOffset]::FromUnixTimeSeconds([int64]$response.expires_at).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss zzz")
} else {
    "No expiry"
}

Write-Host ""
Write-Host "Rootfull test license created." -ForegroundColor Green
Write-Host "License key : $($response.license_key)"
Write-Host "Expires     : $expiryText"
Write-Host "Activate    : TLinkauto > Settings > License > enter the key > Activate"
Write-Host "Verify      : .\scripts\Test-TLinkRootfullLicensePhase2.ps1 -HostIP <IPHONE_IP> -ExpectedMode enforced -ExpectedState valid"

[ordered]@{
    created = [bool]$response.ok
    license_key = $response.license_key
    license_id = $response.id
    status = $response.status
    max_devices = [int]$response.max_devices
    expires_at = [int64]$response.expires_at
    expires_local = $expiryText
    features = @($response.features)
    endpoint = $endpointBase
} | ConvertTo-Json -Depth 5
