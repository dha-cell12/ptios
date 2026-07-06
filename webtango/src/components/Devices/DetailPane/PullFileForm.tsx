import { useState } from 'react';
import { getAdbConnection } from '../../../stores/AdbConnectionRegistry';

// We dynamically import streamsaver to avoid issues in environments that don't support it initially
let streamSaver: any = null;
import('streamsaver').then(m => streamSaver = m.default || m).catch(() => {});

type Props = {
  serial: string;
};

export function PullFileForm({ serial }: Props) {
  const [remotePath, setRemotePath] = useState<string>('');
  const [status, setStatus] = useState<string>('');
  const [isPulling, setIsPulling] = useState(false);

  const handlePull = async () => {
    if (!remotePath.trim()) {
      setStatus('❌ Please enter a valid file path');
      return;
    }

    const adb = getAdbConnection(serial);
    if (!adb) {
      setStatus('❌ Device not connected');
      return;
    }

    setIsPulling(true);
    setStatus('⏳ Checking file...');
    const startTime = performance.now();
    const fileName = remotePath.split('/').pop() || 'downloaded_file';

    try {
      const checkSocket = await adb.createSocket(`shell:stat -c %s "${remotePath}" 2>/dev/null || echo "NOT_FOUND"`);
      const decoder = new TextDecoder();
      let sizeOutput = '';
      for await (const chunk of checkSocket.readable) {
        sizeOutput += decoder.decode(chunk);
      }
      sizeOutput = sizeOutput.trim();

      if (sizeOutput === 'NOT_FOUND' || sizeOutput === '' || isNaN(parseInt(sizeOutput, 10))) {
        setStatus('❌ File not found');
        setIsPulling(false);
        return;
      }

      const expectedSize = parseInt(sizeOutput, 10);
      setStatus(`⏳ Downloading ${(expectedSize / 1024 / 1024).toFixed(2)} MB...`);

      let socket;
      try {
        socket = await adb.createSocket(`exec:cat "${remotePath}"`);
      } catch (execErr) {
        socket = await adb.createSocket(`shell:stty raw -echo 2>/dev/null; cat "${remotePath}"`);
      }

      let writableStream: WritableStream;
      let usingFSA = false;

      // Try File System Access API first
      if ('showSaveFilePicker' in window) {
        try {
          const handle = await (window as any).showSaveFilePicker({
            suggestedName: fileName,
          });
          writableStream = await handle.createWritable();
          usingFSA = true;
        } catch (e: any) {
          if (e.name === 'AbortError') {
            setStatus('❌ Cancelled');
            setIsPulling(false);
            return;
          }
          throw e; // fallback to streamSaver
        }
      }

      if (!usingFSA) {
        if (!streamSaver) throw new Error('StreamSaver not loaded and FSA not supported');
        writableStream = streamSaver.createWriteStream(fileName, {
          size: expectedSize,
        });
      }

      const writer = writableStream!.getWriter();
      let received = 0;
      let lastProgressUpdate = 0;

      for await (const chunk of socket.readable) {
        await writer.write(chunk);
        received += chunk.length;

        if (received - lastProgressUpdate > 256 * 1024) {
          const now = performance.now();
          const elapsed = (now - startTime) / 1000;
          const percent = expectedSize > 0 ? Math.floor((received / expectedSize) * 100) : 0;
          const speedMBps = elapsed > 0 ? received / elapsed / 1024 / 1024 : 0;
          setStatus(`⏳ ${percent}% (${(received / 1024 / 1024).toFixed(1)}/${(expectedSize / 1024 / 1024).toFixed(1)} MB) @ ${speedMBps.toFixed(1)} MB/s`);
          lastProgressUpdate = received;
        }
      }

      await writer.close();
      const duration = (performance.now() - startTime) / 1000;
      const speedMBps = received / duration / 1024 / 1024;
      setStatus(`✅ ${fileName} (${speedMBps.toFixed(1)} MB/s)`);

    } catch (e: any) {
      console.error(`[PullFileForm] Pull error:`, e);
      setStatus(`❌ Error: ${e.message}`);
    } finally {
      setIsPulling(false);
    }
  };

  return (
    <div className="pull-file-wrapper">
      <div className="pull-header">
        <span>Pull File from Device</span>
      </div>
      <p className="pull-desc">
        Enter the absolute file path on Android device to download locally.
      </p>
      <div className="shell-input-group">
        <input
          type="text"
          placeholder="/sdcard/Download/example.txt"
          className="pull-input"
          value={remotePath}
          onChange={e => setRemotePath(e.target.value)}
          disabled={isPulling}
          onKeyDown={(e) => {
            if (e.key === 'Enter') handlePull();
          }}
        />
        <button
          className="shell-run-btn"
          title="Download File"
          onClick={handlePull}
          disabled={isPulling}
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-download"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/></svg>
        </button>
      </div>
      {status && <div className="pull-status-log">{status}</div>}
    </div>
  );
}
