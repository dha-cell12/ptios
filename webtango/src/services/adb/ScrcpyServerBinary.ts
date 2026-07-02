// Lazy cached fetch of the scrcpy server jar. The binary is shipped under /public
// and only needs to be downloaded once per page session.

let cached: Uint8Array | undefined;
let inflight: Promise<Uint8Array> | undefined;

export async function getScrcpyServerBinary(): Promise<Uint8Array> {
  if (cached) return cached;
  if (inflight) return inflight;
  inflight = (async () => {
    const response = await fetch('/scrcpy-server-v3.1');
    if (!response.ok) throw new Error(`Failed to fetch scrcpy server: HTTP ${response.status}`);
    const buffer = await response.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    cached = bytes;
    console.log(`[scrcpy-server] loaded ${bytes.length} bytes`);
    return bytes;
  })();
  try {
    return await inflight;
  } finally {
    inflight = undefined;
  }
}
