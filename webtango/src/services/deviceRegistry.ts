export type UnifiedDevice = {
  id: string;
  platform: string;
  status: string;
  display_name: string;
  meta: any;
  capabilities: string[];
};

export async function listDevices(httpBase: string): Promise<UnifiedDevice[]> {
  const resp = await fetch(`${httpBase}/devices`, { cache: 'no-store' });
  if (!resp.ok) throw new Error(`Failed to list devices: HTTP ${resp.status}`);
  return (await resp.json()) as UnifiedDevice[];
}

export function deviceLabel(device: UnifiedDevice): string {
  const metaName = device.meta?.device?.name || device.meta?.device?.model;
  return device.display_name || metaName || device.id;
}
