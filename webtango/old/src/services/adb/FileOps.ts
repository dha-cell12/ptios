import type { Adb } from '@yume-chan/adb';
import { PackageManager } from '@yume-chan/android-bin';
import { WrapReadableStream } from '@yume-chan/stream-extra';

export type FileOpProgress = {
  phase: 'reading' | 'encoding' | 'transferring' | 'verifying' | 'done' | 'error';
  bytesTransferred?: number;
  bytesTotal?: number;
  percent?: number;
  message?: string;
  bytesPerSec?: number;
};

export type FileOpCallback = (p: FileOpProgress) => void;

export async function installApk(
  adb: Adb,
  file: File,
  onProgress?: FileOpCallback
): Promise<void> {
  onProgress?.({ phase: 'transferring', bytesTotal: file.size, message: `Installing ${file.name}` });
  const pm = new PackageManager(adb);
  const stream = new WrapReadableStream(file.stream() as any);
  try {
    await pm.installStream(file.size, stream as any);
  } catch (streamError: any) {
    // The Yume-chan library throws during stream cleanup even when install succeeds.
    // Detect that specific pattern and swallow it; rethrow real install failures.
    const stack = streamError?.stack || String(streamError);
    if (stack.includes('Promise.all') || stack.includes('index 1')) {
      console.warn('[file-ops] install stream cleanup warning (install actually succeeded)', streamError);
    } else {
      onProgress?.({ phase: 'error', message: String(streamError) });
      throw streamError;
    }
  }
  onProgress?.({ phase: 'done', message: 'Installed' });
}

export async function pushFile(
  adb: Adb,
  file: File,
  destPath?: string,
  onProgress?: FileOpCallback
): Promise<string> {
  const safeName = file.name.replace(/\s+/g, '_');
  const target = destPath ?? `/data/local/tmp/${safeName}`;

  onProgress?.({ phase: 'reading', bytesTotal: file.size });
  const buffer = await file.arrayBuffer();
  const bytes = new Uint8Array(buffer);

  onProgress?.({ phase: 'encoding', bytesTotal: bytes.length });
  const encodingChunkSize = 32768;
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i += encodingChunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + encodingChunkSize));
  }
  const base64Data = btoa(binary);

  const socket = await adb.createSocket(
    `shell:base64 -d > "${target}" && chmod 644 "${target}"`
  );
  const writer = socket.writable.getWriter();
  const encoder = new TextEncoder();
  const chunkSize = 65536;
  let sent = 0;
  const start = performance.now();

  for (let i = 0; i < base64Data.length; i += chunkSize) {
    const chunk = base64Data.substring(i, Math.min(i + chunkSize, base64Data.length));
    await writer.write(encoder.encode(chunk));
    sent += chunk.length;
    const percent = Math.floor((sent / base64Data.length) * 100);
    const elapsedSec = (performance.now() - start) / 1000;
    onProgress?.({
      phase: 'transferring',
      bytesTransferred: sent,
      bytesTotal: base64Data.length,
      percent,
      bytesPerSec: elapsedSec > 0 ? sent / elapsedSec : undefined,
    });
  }
  await writer.close();

  const decoder = new TextDecoder();
  for await (const chunk of socket.readable) {
    const out = decoder.decode(chunk).trim();
    if (out) console.log(`[file-ops] push out: ${out}`);
  }

  onProgress?.({ phase: 'done', message: target });
  return target;
}

export async function pullFile(
  adb: Adb,
  remotePath: string,
  onProgress?: FileOpCallback
): Promise<{ blob: Blob; filename: string; bytes: number }> {
  const trimmed = remotePath.trim();
  if (!trimmed) throw new Error('remote path required');
  const filename = trimmed.split('/').pop() || 'downloaded_file';

  onProgress?.({ phase: 'verifying', message: `Checking ${trimmed}` });

  const sizeSocket = await adb.createSocket(
    `shell:stat -c %s "${trimmed}" 2>/dev/null || echo NOT_FOUND`
  );
  const sizeDecoder = new TextDecoder();
  let sizeOutput = '';
  for await (const chunk of sizeSocket.readable) {
    sizeOutput += sizeDecoder.decode(chunk);
  }
  sizeOutput = sizeOutput.trim();
  if (sizeOutput === 'NOT_FOUND' || sizeOutput === '' || Number.isNaN(parseInt(sizeOutput, 10))) {
    onProgress?.({ phase: 'error', message: 'File not found' });
    throw new Error(`File not found: ${trimmed}`);
  }
  const expectedSize = parseInt(sizeOutput, 10);

  onProgress?.({ phase: 'transferring', bytesTotal: expectedSize });

  let socket;
  try {
    socket = await adb.createSocket(`exec:cat "${trimmed}"`);
  } catch {
    socket = await adb.createSocket(`shell:stty raw -echo 2>/dev/null; cat "${trimmed}"`);
  }

  const chunks: Uint8Array[] = [];
  let received = 0;
  let lastReportAt = 0;
  const start = performance.now();
  for await (const chunk of socket.readable) {
    chunks.push(chunk);
    received += chunk.length;
    if (received - lastReportAt > 256 * 1024) {
      const elapsedSec = (performance.now() - start) / 1000;
      onProgress?.({
        phase: 'transferring',
        bytesTransferred: received,
        bytesTotal: expectedSize,
        percent: expectedSize > 0 ? Math.floor((received / expectedSize) * 100) : undefined,
        bytesPerSec: elapsedSec > 0 ? received / elapsedSec : undefined,
      });
      lastReportAt = received;
    }
  }

  const totalLength = chunks.reduce((sum, c) => sum + c.length, 0);
  const bytes = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }

  if (bytes.length !== expectedSize) {
    console.warn(`[file-ops] size mismatch: received ${bytes.length}, expected ${expectedSize}`);
  }

  const blob = new Blob([bytes], { type: 'application/octet-stream' });
  onProgress?.({
    phase: 'done',
    bytesTransferred: bytes.length,
    bytesTotal: expectedSize,
    message: filename,
  });
  return { blob, filename, bytes: bytes.length };
}

export function triggerBrowserDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
