param(
    [Parameter(Mandatory = $true)]
    [string]$HostIP,
    [int]$Port = 6000,
    [int]$TimeoutMs = 30000,
    [switch]$ClearAlbum
)

$ErrorActionPreference = "Stop"

function Invoke-TLinkPhotoTask {
    param([Parameter(Mandatory = $true)][string]$Task)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.ReceiveTimeout = $TimeoutMs
        $client.SendTimeout = 5000
        $client.Connect($HostIP, $Port)
        $stream = $client.GetStream()
        $request = [Text.Encoding]::UTF8.GetBytes("$Task`r`n")
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

$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$deviceImagePath = "/var/mobile/Library/TLinkauto/tmp/photo-tcc-test-$stamp.png"
$capture = Invoke-TLinkPhotoTask -Task "291;;$deviceImagePath"
if ($capture -ne "0;;$deviceImagePath") {
    throw "Screenshot capture failed: $capture"
}

$save = Invoke-TLinkPhotoTask -Task "292;;$deviceImagePath"
if ($save -notlike "0;;saved_to_album;;TLinkauto*") {
    throw "Zero-touch Photos save failed: $save"
}

$clear = "not_requested"
if ($ClearAlbum) {
    $clear = Invoke-TLinkPhotoTask -Task "293"
    if ($clear -notlike "0;;album_*") {
        throw "Album clear failed: $clear"
    }
}

[pscustomobject]@{
    host = $HostIP
    device_image_path = $deviceImagePath
    capture = $capture
    save = $save
    clear = $clear
    decision = "pass_zero_touch_photos"
} | Format-List
