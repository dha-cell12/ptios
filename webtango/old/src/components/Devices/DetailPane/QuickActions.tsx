import { useRef, useState } from 'react';
import { installApk } from '../../../services/adb/FileOps';
import { getAdbConnection } from '../../../stores/AdbConnectionRegistry';
import { getMirrorSession } from '../../../stores/ScrcpyMirrorStore';

type Props = {
  serial: string;
};

type Status = { kind: 'idle' | 'busy' | 'ok' | 'error'; message?: string };

function takeScreenshot(serial: string): { blob: Promise<Blob | null>; filename: string } | undefined {
  const session = getMirrorSession(serial);
  if (!session) return undefined;
  const filename = `screenshot-${serial}-${Date.now()}.png`;
  const blob = new Promise<Blob | null>((resolve) => {
    session.hiddenCanvas.toBlob((b) => resolve(b), 'image/png');
  });
  return { blob, filename };
}

function triggerDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

export function QuickActions({ serial }: Props) {
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [screenshotStatus, setScreenshotStatus] = useState<Status>({ kind: 'idle' });
  const [installStatus, setInstallStatus] = useState<Status>({ kind: 'idle' });

  const handleScreenshot = async () => {
    setScreenshotStatus({ kind: 'busy' });
    const capture = takeScreenshot(serial);
    if (!capture) {
      setScreenshotStatus({ kind: 'error', message: 'Mirror not ready' });
      return;
    }
    try {
      const blob = await capture.blob;
      if (!blob) throw new Error('Empty frame');
      triggerDownload(blob, capture.filename);
      setScreenshotStatus({ kind: 'ok', message: 'Saved' });
    } catch (e) {
      setScreenshotStatus({ kind: 'error', message: String(e) });
    }
  };

  const handleInstallClick = () => {
    fileInputRef.current?.click();
  };

  const handleFileSelected = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    const adb = getAdbConnection(serial);
    if (!adb) {
      setInstallStatus({ kind: 'error', message: 'Device not connected' });
      return;
    }
    setInstallStatus({ kind: 'busy', message: `Installing ${file.name}` });
    try {
      await installApk(adb, file, (p) => {
        if (p.phase === 'error') {
          setInstallStatus({ kind: 'error', message: p.message });
        } else if (p.phase === 'done') {
          setInstallStatus({ kind: 'ok', message: 'Installed' });
        }
      });
    } catch (err) {
      setInstallStatus({ kind: 'error', message: String(err) });
    }
  };

  return (
    <div className="quick-actions">
      <button
        type="button"
        className="action-btn btn-screenshot"
        onClick={handleScreenshot}
        disabled={screenshotStatus.kind === 'busy'}
      >
        {screenshotStatus.kind === 'busy' ? 'Capturing...' : 'Screenshot'}
      </button>
      <button
        type="button"
        className="action-btn btn-install"
        onClick={handleInstallClick}
        disabled={installStatus.kind === 'busy'}
      >
        {installStatus.kind === 'busy' ? 'Installing...' : 'Install APK'}
      </button>
      <input
        ref={fileInputRef}
        type="file"
        accept=".apk"
        style={{ display: 'none' }}
        onChange={handleFileSelected}
      />
      {(screenshotStatus.message || installStatus.message) && (
        <div className="quick-action-status">
          {screenshotStatus.message && (
            <span className={`status-line status-${screenshotStatus.kind}`}>
              Screenshot: {screenshotStatus.message}
            </span>
          )}
          {installStatus.message && (
            <span className={`status-line status-${installStatus.kind}`}>
              Install: {installStatus.message}
            </span>
          )}
        </div>
      )}
    </div>
  );
}
