# Remote iOS MVP

## Scope

This transport lets `streamd` make an outbound connection when an iPhone is
not reachable through LAN scanning. Existing LAN discovery and direct ports
remain unchanged.

```text
iPhone Wi-Fi/5G
  -> WSS control + on-demand WSS H264
  -> Cloudflare Tunnel
  -> bridge-rs-new on Windows :15037
  -> existing WebRTC/TURN
  -> Webtango
```

Control and video use separate WebSockets. Video carries one complete `ZXH2`
frame per binary WebSocket message and bridge-rs forwards its H264 payload to
the existing WebRTC track without re-encoding.

## 1. Configure Windows Bridge

Generate a random test token of at least 32 bytes. Keep it private.

```powershell
$bytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$token = [Convert]::ToBase64String($bytes)
$env:TLINK_REMOTE_TOKEN = $token

# Start this build from the same PowerShell process so it receives the token.
./target/release/tango_bridge.exe
```

For a tray app started automatically, set `TLINK_REMOTE_TOKEN` as a persistent
user environment variable before starting the process. Restart an already
running bridge after changing the variable.

Point the existing Cloudflare Tunnel hostname at:

```text
http://127.0.0.1:15037
```

The tunnel must pass WebSocket upgrade requests for all paths, including:

- `/remote/device/control`
- `/remote/device/video`
- `/ios/*/tlinkauto`
- `/ios/*/rtc/offer`
- `/bridge/`

Verify the public endpoint and token:

```powershell
$domain = "https://bridge.example.com"
$headers = @{ Authorization = "Bearer $token" }
Invoke-RestMethod "$domain/remote/device/status" -Headers $headers
```

From the repository root, the combined status/registry probe is:

```powershell
./scripts/Test-TLinkRemoteBridge.ps1 `
  -Domain "https://bridge.example.com" `
  -Token $token `
  -ExpectedDevices 0
```

Expected before connecting an iPhone:

```text
enabled           : True
connected_devices : 0
protocol          : tlink-remote-wss-v1
```

An incorrect or missing token must return HTTP `401`.

## 2. Configure StreamControl

Install the service-v23 TIPA and open StreamControl once so its supervisor
replaces the previous `streamd`.

Open `Settings -> Remote Bridge`, then enter:

- URL: `wss://bridge.example.com` (no `/bridge/` or API path)
- Token: the exact value used by `TLINK_REMOTE_TOKEN`
- Tap `Save & Enable`

`streamd` watches the plist and connects within about five seconds; restarting
the daemon is not required after normal settings changes.

Use `Settings -> DEBUG -> Remote Bridge Status`. A healthy connection contains:

```text
state = connected
connected = 1
last_error = ""
```

Task `60` also includes the `remote_bridge` diagnostics object. The token is
never included in task output or the diagnostics file.

## 3. Test Over 5G

1. Disable Wi-Fi on the iPhone and leave cellular data enabled.
2. Wait five to ten seconds for WSS reconnect.
3. Check the bridge status again; `connected_devices` must be `1`.
   You can rerun `Test-TLinkRemoteBridge.ps1` with `-ExpectedDevices 1`.
4. Confirm the remote device is registered:

```powershell
Invoke-RestMethod "$domain/devices" | ConvertTo-Json -Depth 8
```

The device should have an ID beginning with `ios-remote:`, transport
`remote_wss`, and capabilities `stream_rtc_auto`, `tlinkauto`, `remote_wss`.

5. In Webtango, connect to `wss://bridge.example.com/bridge/`.
6. Open the remote iPhone. Webtango automatically locks this device to RTC.
7. Verify live video, tap, swipe, task responses, and reconnection after toggling
   between Wi-Fi and 5G.

If the browser and bridge cannot establish a direct WebRTC path, the existing
TURN configuration is used. The iPhone-to-bridge WSS leg still goes through the
Cloudflare Tunnel in this MVP.

## Diagnostics

Bridge console:

```text
[remote-ios] online id=ios-remote:<device-id> service_version=23
[ios-rtc] remote video requested ... profile=wan
```

iPhone diagnostics:

```text
/var/mobile/Library/TLinkauto/runtime/remote_bridge.plist
```

Common states:

- `invalid_configuration`: URL is not `ws/wss`, or token is shorter than 16 characters.
- `license_blocked`: automation license is not currently effective.
- `connecting`: handshake is pending or the network is changing.
- `disconnected`: inspect `last_error`, Cloudflare routing, and bridge process environment.
- `connected`: control WSS is healthy; video WSS is created only while viewing.

## MVP Security Limits

`TLINK_REMOTE_TOKEN` is a pre-shared test secret. It authenticates the device
endpoint but is stored in plaintext in the iPhone settings plist. It is not a
replacement for the planned signed per-device session challenge, token rotation,
replay protection, or authenticated browser control. Use a dedicated hostname,
a long random token, TLS (`wss://`), and rotate the token after testing.
