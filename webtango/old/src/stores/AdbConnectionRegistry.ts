import type { Adb } from '@yume-chan/adb';

// Slice D1 bridge: legacy main.ts owns the AdbServerClient + connectedDevices
// Map for now. React panels need the Adb instance to drive FileOps. This
// registry is a thin map kept in sync from main.ts (connect/disconnect) until
// Slice C-hoàn tất migrates ownership into a service.

const adbInstances = new Map<string, Adb>();

export function registerAdbConnection(serial: string, adb: Adb) {
  adbInstances.set(serial, adb);
}

export function unregisterAdbConnection(serial: string) {
  adbInstances.delete(serial);
}

export function getAdbConnection(serial: string): Adb | undefined {
  return adbInstances.get(serial);
}
