// Bidirectional clipboard sync between the host browser and a scrcpy-controlled
// Android device, with a cooldown guard so that what we just pushed in one
// direction does not immediately bounce back the other way.

export const CLIPBOARD_SYNC_COOLDOWN_MS = 1000;

type SyncState = {
  lastDeviceValue: string;
  lastSyncTime: number;
};

const state = new Map<string, SyncState>();

export function recordDeviceToBrowser(serial: string, value: string) {
  state.set(serial, { lastDeviceValue: value, lastSyncTime: Date.now() });
}

export function shouldSkipBrowserToDevice(serial: string, candidate: string): boolean {
  const s = state.get(serial);
  if (!s) return false;
  if (Date.now() - s.lastSyncTime < CLIPBOARD_SYNC_COOLDOWN_MS) return true;
  if (candidate === s.lastDeviceValue) return true;
  return false;
}

export function reset(serial?: string) {
  if (serial) state.delete(serial);
  else state.clear();
}

export async function readBrowserClipboardOrEmpty(): Promise<string> {
  try {
    if (!navigator.clipboard) return '';
    return await navigator.clipboard.readText();
  } catch {
    return '';
  }
}

export async function writeBrowserClipboard(text: string): Promise<boolean> {
  try {
    if (!navigator.clipboard) return false;
    await navigator.clipboard.writeText(text);
    return true;
  } catch (e) {
    console.warn('[clipboard-sync] writeText failed', e);
    return false;
  }
}
