import { useEffect, useMemo, useRef } from 'react';
import { useStore } from '../../stores/useStore';
import { adbDeviceStore } from '../../stores/AdbDeviceStore';
import { iosDeviceStore, iosGridStreams } from '../../stores/IosDeviceStore';
import { bridgeStore } from '../../stores/BridgeStore';
import { uiStore, setScreenViewMode, setScreenViewPlatform, setScreenViewZoom } from '../../stores/UiStore';
import { modalActions } from '../../stores/ModalStore';
import { useCanvasBinding } from '../../hooks/useCanvasBinding';
import { useDeviceControl } from '../../hooks/useDeviceControl';
import type { UnifiedDevice } from '../../services/deviceRegistry';
import type { AdbDeviceRecord } from '../../services/adb/AdbDeviceManager';

// Multi-device grid. Android cells share CanvasDrawRegistry with the detail
// pane (so the same decoded frames blit into both views without extra work).
// iOS cells spawn their own OffscreenCanvas worker via IosGridStreams.
export function ScreenViewGrid() {
  const mode = useStore(uiStore, (s) => s.screenViewMode);
  const platform = useStore(uiStore, (s) => s.screenViewPlatform);
  const zoom = useStore(uiStore, (s) => s.screenViewZoom);
  const adbOrder = useStore(adbDeviceStore, (s) => s.order);
  const adbDevices = useStore(adbDeviceStore, (s) => s.devices);
  const iosDevices = useStore(iosDeviceStore, (s) => s.devices);

  const cardWidth = mode === 'focus' ? 360 : Math.round(240 * zoom);

  const adbList = useMemo(
    () => adbOrder.map((s) => adbDevices[s]).filter(Boolean) as AdbDeviceRecord[],
    [adbOrder, adbDevices]
  );

  return (
    <section className="screen-view-pane-modern" style={{ display: 'flex', flexDirection: 'column', width: '100%', height: '100%', overflow: 'hidden', background: 'var(--background)' }}>
      <Toolbar mode={mode} platform={platform} zoom={zoom} />
      <div style={{ flex: 1, overflowY: 'auto', padding: 24, background: '#f8fafc' }}>
        <div
          className="screen-grid"
          style={{
            display: mode === 'focus' ? 'flex' : 'grid',
            justifyContent: mode === 'focus' ? 'center' : undefined,
            alignItems: mode === 'focus' ? 'flex-start' : undefined,
            gridTemplateColumns: mode === 'grid' ? `repeat(auto-fill, minmax(${cardWidth}px, 1fr))` : undefined,
            gap: 16,
          }}
        >
          {platform === 'android'
            ? (adbList.length === 0
                ? <EmptyState title="No Android Devices" body="Connect Android devices to show live mirrors." />
                : adbList.map((d) => <AndroidGridCard key={d.serial} serial={d.serial} model={d.properties?.model} width={cardWidth} />))
            : (iosDevices.length === 0
                ? <EmptyState title="No iOS Devices" body="Switch on TLinkauto and wait for discovery." />
                : iosDevices.map((d) => <IosGridCard key={d.id} device={d} width={cardWidth} />))}
        </div>
      </div>
    </section>
  );
}

function Toolbar({ mode, platform, zoom }: { mode: string; platform: string; zoom: number }) {
  const percent = ((zoom - 0.4) / 1.1) * 100;

  return (
    <div className="screen-view-toolbar">
      <div className="toolbar-left">
        <span className="toolbar-title" style={{ fontWeight: 600, fontSize: 14, color: 'var(--foreground)' }}>Screen Mirroring Grid</span>
      </div>
      <div className="toolbar-right" style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
        <ToggleGroup
          value={platform}
          options={[{ id: 'android', label: 'Android' }, { id: 'ios', label: 'iOS' }]}
          onChange={(v) => setScreenViewPlatform(v as 'android' | 'ios')}
        />
        <ToggleGroup
          value={mode}
          options={[{ id: 'grid', label: 'Grid Mode' }, { id: 'focus', label: 'Focus Mode' }]}
          onChange={(v) => setScreenViewMode(v as 'grid' | 'focus')}
        />
        <div className="zoom-slider-container">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="zoom-icon"
          >
            <circle cx="11" cy="11" r="8" />
            <line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <input
            type="range"
            min={0.4}
            max={1.5}
            step={0.1}
            value={zoom}
            onChange={(e) => setScreenViewZoom(parseFloat(e.target.value))}
            className="zoom-slider"
            style={{
              background: `linear-gradient(to right, var(--primary) 0%, var(--primary) ${percent}%, var(--border) ${percent}%, var(--border) 100%)`
            }}
          />
          <span className="zoom-label">{Math.round(zoom * 100)}%</span>
        </div>
      </div>
    </div>
  );
}

function ToggleGroup({ value, options, onChange }: {
  value: string;
  options: { id: string; label: string }[];
  onChange: (id: string) => void;
}) {
  return (
    <div className="view-mode-toggle-group" style={{ background: 'var(--secondary)', border: '1px solid var(--border)', borderRadius: 8, padding: 3, display: 'flex', gap: 2 }}>
      {options.map((opt) => (
        <button
          key={opt.id}
          type="button"
          className={`view-toggle-btn ${value === opt.id ? 'active' : ''}`}
          onClick={() => onChange(opt.id)}
        >
          {opt.label}
        </button>
      ))}
    </div>
  );
}

function AndroidGridCard({ serial, model, width }: { serial: string; model: string | undefined; width: number }) {
  const ref = useRef<HTMLCanvasElement | null>(null);
  useCanvasBinding(serial, ref, { mode: 'native' } as any);
  useDeviceControl(serial, ref);

  return (
    <div className="device-screen-card" style={{ width }} onDoubleClick={(e) => {
      e.preventDefault();
      modalActions.openAndroidModal(serial);
    }}>
      <div className="screen-frame">
        <div className="screen-canvas-wrapper">
          <canvas ref={ref} />
        </div>
      </div>
      <div className="device-label">{model || serial}</div>
    </div>
  );
}

function IosGridCard({ device, width }: { device: UnifiedDevice; width: number }) {
  const bridgeUrl = useStore(bridgeStore, (s) => s.url);
  const wrapperRef = useRef<HTMLDivElement | null>(null);

  // Worker-backed iOS streams: attach on mount, stop on unmount.
  useEffect(() => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return;

    // Create a fresh canvas manually to survive React StrictMode double-invocations.
    // HTMLCanvasElement.transferControlToOffscreen() can only be called once per canvas.
    const canvas = document.createElement('canvas');
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    canvas.style.objectFit = 'fill';
    wrapper.appendChild(canvas);

    iosGridStreams.start(device, canvas, bridgeUrl);
    
    return () => {
      iosGridStreams.stop(device.id);
      if (wrapper.contains(canvas)) {
        wrapper.removeChild(canvas);
      }
    };
  }, [device.id, bridgeUrl]);

  return (
    <div className="device-screen-card ios-screen-card" style={{ width }} onDoubleClick={(e) => {
      e.preventDefault();
      modalActions.openIosModal(device.id);
    }}>
      <div className="screen-frame">
        <div className="screen-canvas-wrapper" ref={wrapperRef}>
          {/* Canvas is injected here by useEffect */}
        </div>
      </div>
      <div className="device-label">{device.name || device.id}</div>
    </div>
  );
}

function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="empty-state" style={{ padding: 24, textAlign: 'center', color: 'var(--muted-foreground)' }}>
      <h3 style={{ margin: '0 0 4px', fontSize: 15 }}>{title}</h3>
      <p style={{ margin: 0, fontSize: 13 }}>{body}</p>
    </div>
  );
}
