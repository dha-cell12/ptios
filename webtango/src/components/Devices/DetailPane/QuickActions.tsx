import { useRef, useState } from 'react';
import { installApk, pushFile } from '../../../services/adb/FileOps';
import { getAdbConnection } from '../../../stores/AdbConnectionRegistry';
import { getMirrorSession } from '../../../stores/ScrcpyMirrorStore';

type Props = {
  serial: string;
  onToggleShell?: () => void;
  onTogglePull?: () => void;
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

export function QuickActions({ serial, onToggleShell, onTogglePull }: Props) {
  const apkInputRef = useRef<HTMLInputElement | null>(null);
  const pushInputRef = useRef<HTMLInputElement | null>(null);
  const [screenshotStatus, setScreenshotStatus] = useState<Status>({ kind: 'idle' });
  const [installStatus, setInstallStatus] = useState<Status>({ kind: 'idle' });
  const [pushStatus, setPushStatus] = useState<Status>({ kind: 'idle' });

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

  const handleApkSelected = async (e: React.ChangeEvent<HTMLInputElement>) => {
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
        } else if (p.phase === 'transferring') {
          setInstallStatus({ kind: 'busy', message: `Installing ${file.name}` });
        }
      });
    } catch (err) {
      setInstallStatus({ kind: 'error', message: String(err) });
    }
  };

  const handlePushSelected = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    const adb = getAdbConnection(serial);
    if (!adb) {
      setPushStatus({ kind: 'error', message: 'Device not connected' });
      return;
    }
    setPushStatus({ kind: 'busy', message: `Pushing ${file.name}` });
    try {
      await pushFile(adb, file, undefined, (p) => {
        if (p.phase === 'error') {
          setPushStatus({ kind: 'error', message: p.message });
        } else if (p.phase === 'done') {
          setPushStatus({ kind: 'ok', message: 'Pushed' });
        } else if (p.phase === 'transferring') {
          setPushStatus({ kind: 'busy', message: `Pushing ${p.percent}%` });
        }
      });
    } catch (err) {
      setPushStatus({ kind: 'error', message: String(err) });
    }
  };

  return (
    <div className="collapsible-section open">
      <div className="collapsible-header">
        <span>Quick Actions</span>
        <span className="collapse-icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-chevron-down"><path d="m6 9 6 6 6-6"/></svg>
        </span>
      </div>
      <div className="collapsible-content">
        <div className="detail-actions-bar">
          <button className="detail-action-btn btn-screenshot" onClick={handleScreenshot} disabled={screenshotStatus.kind === 'busy'}>
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-camera"><path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/></svg>
            {screenshotStatus.kind === 'busy' ? 'Capturing...' : 'Screenshot'}
          </button>
          
          <button className="detail-action-btn btn-install" onClick={() => apkInputRef.current?.click()} disabled={installStatus.kind === 'busy'}>
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-download-cloud"><path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"/><path d="M12 12v9"/><path d="m8 17 4 4 4-4"/></svg>
            {installStatus.kind === 'busy' ? installStatus.message : 'Install APK'}
          </button>
          <input ref={apkInputRef} type="file" accept=".apk" style={{ display: 'none' }} onChange={handleApkSelected} />

          <button className="detail-action-btn btn-upload" onClick={() => pushInputRef.current?.click()} disabled={pushStatus.kind === 'busy'}>
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-upload"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/></svg>
            {pushStatus.kind === 'busy' ? pushStatus.message : 'Push File'}
          </button>
          <input ref={pushInputRef} type="file" style={{ display: 'none' }} onChange={handlePushSelected} />

          <button className="detail-action-btn btn-download" onClick={onTogglePull}>
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-download"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/></svg>
            Pull File
          </button>

          <button className="detail-action-btn btn-shell" onClick={onToggleShell}>
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-terminal"><polyline points="4 17 10 11 4 5"/><line x1="12" x2="20" y1="19" y2="19"/></svg>
            Console
          </button>
        </div>
        {(screenshotStatus.message || installStatus.message || pushStatus.message) && (
          <div className="quick-action-status" style={{ padding: '8px 16px', fontSize: '12px' }}>
            {screenshotStatus.message && <div className={`status-line status-${screenshotStatus.kind}`}>Screenshot: {screenshotStatus.message}</div>}
            {installStatus.message && <div className={`status-line status-${installStatus.kind}`}>Install: {installStatus.message}</div>}
            {pushStatus.message && <div className={`status-line status-${pushStatus.kind}`}>Push: {pushStatus.message}</div>}
          </div>
        )}
      </div>
    </div>
  );
}
