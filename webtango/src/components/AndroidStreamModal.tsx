import { useRef } from 'react';
import { useStore } from '../stores/useStore';
import { adbDeviceStore } from '../stores/AdbDeviceStore';
import { modalStore, modalActions } from '../stores/ModalStore';
import { useCanvasBinding } from '../hooks/useCanvasBinding';
import { AndroidKeyCode } from '@yume-chan/scrcpy';
import { getMirrorSession } from '../stores/ScrcpyMirrorStore';

import { ScrcpyBatchController } from '../ScrcpyBatchController';
import { useDeviceControl } from '../hooks/useDeviceControl';

async function pressKey(serial: string, keyCode: number) {
  const session = getMirrorSession(serial);
  const scrcpyController = session?.controller;
  if (!scrcpyController) {
    console.warn('[AndroidStreamModal] No scrcpy controller for key injection:', serial);
    return;
  }
  try {
    await ScrcpyBatchController.injectKey(scrcpyController, keyCode);
  } catch (e) {
    console.warn('[AndroidStreamModal] keyevent failed', e);
  }
}

import { useDraggable } from '../hooks/useDraggable';

export function AndroidStreamModal() {
  const serial = useStore(modalStore, (s) => s.androidModalSerial);
  const device = useStore(adbDeviceStore, (s) => serial ? s.devices[serial] : undefined);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const contentRef = useRef<HTMLDivElement | null>(null);
  const headerRef = useRef<HTMLDivElement | null>(null);

  // Use native mode to set internal canvas size equal to the stream resolution,
  // matching our custom object-fit coordinate mapper.
  useCanvasBinding(serial || undefined, canvasRef, { mode: 'native' });
  useDeviceControl(serial || undefined, canvasRef);
  useDraggable(contentRef, headerRef, serial);

  if (!serial || !device) return null;

  const model = device.properties?.model || serial;

  return (
    <div className="modal">
      <div className="android-floating-wrapper" ref={contentRef}>
        
        {/* Card 1: Phone Screen Frame */}
        <div className="android-screen-card-floating">
          <div className="android-screen-frame-inner">
            <canvas ref={canvasRef} className="android-canvas-floating" />
          </div>
        </div>

        {/* Card 2: Vertical Control Bar */}
        <div className="android-vertical-toolbar">
          {/* Back Button (Teal circle at top) */}
          <button className="toolbar-btn btn-back" title="Back" onClick={() => pressKey(serial, AndroidKeyCode.AndroidBack)}>
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 18 9 12 15 6" /></svg>
          </button>
          
          <div className="toolbar-divider" />
          
          {/* Power Button */}
          <button className="toolbar-btn" title="Power" onClick={() => pressKey(serial, AndroidKeyCode.Power)}>
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M18.36 6.64a9 9 0 1 1-12.73 0" /><line x1="12" y1="2" x2="12" y2="12" /></svg>
          </button>
          
          {/* Volume Up */}
          <button className="toolbar-btn" title="Volume Up" onClick={() => pressKey(serial, 24)}>
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" /><path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07" /></svg>
          </button>
          
          {/* Volume Down */}
          <button className="toolbar-btn" title="Volume Down" onClick={() => pressKey(serial, 25)}>
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" /><path d="M15.54 8.46a5 5 0 0 1 0 7.07" /></svg>
          </button>
          
          {/* Camera (Screenshot shortcut) */}
          <button className="toolbar-btn" title="Screenshot" onClick={() => console.log('Screenshot click')}>
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z" /><circle cx="12" cy="13" r="3" /></svg>
          </button>
          
          {/* Link with + badge */}
          <div className="btn-badge-wrapper">
            <button className="toolbar-btn" title="Connection Info">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" /><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" /></svg>
            </button>
            <span className="badge-plus">+</span>
          </div>
          
          {/* SYNC Toggle */}
          <div className="toolbar-sync-container">
            <span className="sync-label">SYNC</span>
            <label className="sync-toggle-switch">
              <input type="checkbox" defaultChecked />
              <span className="sync-toggle-slider" />
            </label>
          </div>
          
          {/* Code Icon */}
          <button className="toolbar-btn" title="Developer Console">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="16 18 22 12 16 6" /><polyline points="8 6 2 12 8 18" /></svg>
          </button>
          
          {/* Shield Icon */}
          <button className="toolbar-btn" title="Security">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" /></svg>
          </button>
          
          {/* Location pin */}
          <button className="toolbar-btn" title="Location">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" /><circle cx="12" cy="10" r="3" /></svg>
          </button>

          {/* D-Pad / Navigation Arrows */}
          <div className="toolbar-dpad">
            <button className="dpad-btn up" title="Up" onClick={() => pressKey(serial, 19)}>
              <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><polyline points="18 15 12 9 6 15" /></svg>
            </button>
            <div className="dpad-row">
              <button className="dpad-btn left" title="Left" onClick={() => pressKey(serial, 21)}>
                <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 18 9 12 15 6" /></svg>
              </button>
              <button className="dpad-btn right" title="Right" onClick={() => pressKey(serial, 22)}>
                <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><polyline points="9 18 15 12 9 6" /></svg>
              </button>
            </div>
            <button className="dpad-btn down" title="Down" onClick={() => pressKey(serial, 20)}>
              <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><polyline points="6 9 12 15 18 9" /></svg>
            </button>
          </div>
          
          {/* Stack Icon (Recent Apps) */}
          <button className="toolbar-btn" title="Recent Apps" onClick={() => pressKey(serial, 187)}>
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2" /><line x1="9" y1="3" x2="9" y2="21" /></svg>
          </button>
          
          {/* Home Icon */}
          <button className="toolbar-btn btn-home-round" title="Home" onClick={() => pressKey(serial, AndroidKeyCode.AndroidHome)}>
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /><polyline points="9 22 9 12 15 12 15 22" /></svg>
          </button>
        </div>

        {/* Card 3: Details Panel / Control Sidebar */}
        <div className="android-detail-sidebar">
          {/* Drag Handle & Close */}
          <div className="sidebar-header" ref={headerRef}>
            <button className="header-close-btn" onClick={modalActions.closeAndroidModal} title="Close panel">✕</button>
            <div className="header-pill">13</div>
            <div className="header-drag-handle" title="Drag to move panel">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="5 9 2 12 5 15" /><polyline points="9 5 12 2 15 5" /><polyline points="15 19 12 22 9 19" /><polyline points="19 9 22 12 19 15" /><line x1="2" y1="12" x2="22" y2="12" /><line x1="12" y1="2" x2="12" y2="22" /></svg>
            </div>
          </div>
          
          {/* Device metadata */}
          <div className="sidebar-meta-row">
            <span className="battery-icon">🔋</span>
            <span className="meta-text">{model} • Android (webtango)</span>
          </div>

          <div className="sidebar-scrollable-content">
            {/* Clipboard Action */}
            <button className="sidebar-action-btn-full" title="Get Clipboard" onClick={() => console.log('Get Clipboard click')}>
              <span className="btn-icon">📋</span> Get Clipboard
            </button>
            
            {/* Grid of Action Buttons */}
            <div className="sidebar-grid-actions">
              <button className="grid-action-btn">Set Proxy</button>
              <button className="grid-action-btn">Clear Proxy</button>
              <button className="grid-action-btn">Set Location</button>
              <button className="grid-action-btn">Clear Location</button>
              <button className="grid-action-btn purple-btn"><span className="btn-icon">📸</span> ScrShot</button>
              <button className="grid-action-btn blue-btn"><span className="btn-icon">🌐</span> ShowIP</button>
              <button className="grid-action-btn">FIX SCREEN</button>
              <button className="grid-action-btn">ACTIVE KEY</button>
              <button className="grid-action-btn">Import</button>
              <button className="grid-action-btn">Clean</button>
            </div>

            {/* Applications Title Row */}
            <div className="sidebar-section-header">
              <span className="section-title">Applications</span>
              <button className="section-action-btn kill-btn">Kill all apps</button>
            </div>

            {/* Grid of App Buttons */}
            <div className="sidebar-apps-grid">
              <button className="app-btn"><span className="app-icon fb-icon">f</span> Facebook</button>
              <button className="app-btn"><span className="app-icon msger-icon">💬</span> Messenger</button>
              <button className="app-btn"><span className="app-icon insta-icon">📸</span> Instagram</button>
              <button className="app-btn"><span className="app-icon tele-icon">✈</span> Telegram</button>
              <button className="app-btn"><span className="app-icon tiktok-icon">🎵</span> TikTok</button>
              <button className="app-btn"><span className="app-icon safari-icon">🧭</span> Safari</button>
              <button className="app-btn"><span className="app-icon settings-icon">⚙</span> Settings</button>
            </div>
          </div>
        </div>

      </div>
    </div>
  );
}
