export type WorkspaceRoot = 'scripts' | 'templates' | 'logs';

export type FileEntry = {
  name: string;
  path: string;
  kind: 'file' | 'directory';
  size: number;
  modifiedMs: number;
};

export type FileListResponse = {
  root: WorkspaceRoot;
  path: string;
  entries: FileEntry[];
};

export type FileReadResponse = {
  root: WorkspaceRoot;
  path: string;
  content: string;
};

export async function listWorkspaceFiles(httpBase: string, root: WorkspaceRoot, path = '/'): Promise<FileListResponse> {
  const params = new URLSearchParams({ root, path });
  const resp = await fetch(`${httpBase}/api/files?${params}`, { cache: 'no-store' });
  if (!resp.ok) throw new Error(`Failed to list ${root}: HTTP ${resp.status}`);
  return (await resp.json()) as FileListResponse;
}

export async function readWorkspaceFile(httpBase: string, root: WorkspaceRoot, path: string): Promise<FileReadResponse> {
  const params = new URLSearchParams({ root, path });
  const resp = await fetch(`${httpBase}/api/file?${params}`, { cache: 'no-store' });
  if (!resp.ok) throw new Error(`Failed to read ${path}: HTTP ${resp.status}`);
  return (await resp.json()) as FileReadResponse;
}

export async function writeWorkspaceFile(httpBase: string, root: WorkspaceRoot, path: string, content: string) {
  const resp = await fetch(`${httpBase}/api/file`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ root, path, content }),
  });
  if (!resp.ok) throw new Error(`Failed to save ${path}: HTTP ${resp.status}`);
  return (await resp.json()) as { ok: boolean; backupPath?: string };
}

export function defaultScriptPath(entries: FileEntry[]): string {
  return entries.find((entry) => entry.kind === 'file' && entry.name.endsWith('.js'))?.path || '/demo.js';
}
