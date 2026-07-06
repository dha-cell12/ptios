import React, { useEffect, useRef, useState } from 'react';
import { useStore } from '../../stores/useStore';
import { modalStore, modalActions } from '../../stores/ModalStore';
import { bridgeStore } from '../../stores/BridgeStore';
import { iosDeviceStore } from '../../stores/IosDeviceStore';
import { IosStreamService, IosStreamProfile } from '../../services/ios/IosStreamService';
import { IosControlService } from '../../services/ios/IosControlService';

import { deriveBridgeBases } from '../../services/bridgeBase';
import { useDraggable } from '../../hooks/useDraggable';

export function IosStreamModal() {
  const serial = useStore(modalStore, (s) => s.iosModalSerial);
  const bridgeUrl = useStore(bridgeStore, (s) => s.url);
  const devices = useStore(iosDeviceStore, (s) => s.devices);
  const device = devices.find((d) => d.id === serial);

  const [profile, setProfile] = useState<IosStreamProfile>('fast');
  const [latencyText, setLatencyText] = useState('Waiting for metrics...');

  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const workerCanvasRef = useRef<HTMLCanvasElement>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const latencyOverlayRef = useRef<HTMLDivElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);
  const headerRef = useRef<HTMLDivElement>(null);

  const streamService = useRef(new IosStreamService());
  const controlService = useRef(new IosControlService());

  useDraggable(contentRef, headerRef, serial);

  useEffect(() => {
    if (!serial || !device || !bridgeUrl) return;

    const { wsBase, httpBase } = deriveBridgeBases(bridgeUrl);
    
    streamService.current.mount({
      canvas: canvasRef.current!,
      workerCanvas: workerCanvasRef.current!,
      video: videoRef.current!,
      latencyOverlay: latencyOverlayRef.current!,
    });

    streamService.current.start(serial, wsBase, httpBase, profile);
    controlService.current.start(serial, wsBase);

    return () => {
      streamService.current.unmount();
      controlService.current.stop();
    };
  }, [serial, profile, bridgeUrl, device]);

  useEffect(() => {
    const container = containerRef.current;
    const controls = controlService.current;
    if (!container || !serial) return;

    const onPointerDown = (e: PointerEvent) => controls.handlePointerDown(e, container);
    const onPointerMove = (e: PointerEvent) => controls.handlePointerMove(e, container);
    const onPointerUp = (e: PointerEvent) => controls.handlePointerUp(e, container);
    const onPointerCancel = (e: PointerEvent) => controls.handlePointerCancel(e, container);

    container.addEventListener('pointerdown', onPointerDown);
    container.addEventListener('pointermove', onPointerMove);
    container.addEventListener('pointerup', onPointerUp);
    container.addEventListener('pointercancel', onPointerCancel);

    return () => {
      container.removeEventListener('pointerdown', onPointerDown);
      container.removeEventListener('pointermove', onPointerMove);
      container.removeEventListener('pointerup', onPointerUp);
      container.removeEventListener('pointercancel', onPointerCancel);
    };
  }, [serial]);

  if (!serial || !device) return null;

  return (
    <div className="modal" style={{ display: 'flex' }}>
      <div className="modal-content ios-modal-content" ref={contentRef}>
        <div className="modal-header" ref={headerRef}>
          <h2>{device.display_name || device.id}</h2>
          <div className="ios-mode-toggle">
            {(['fast', 'rtc', 'worker', 'eco'] as IosStreamProfile[]).map((p) => (
              <button
                key={p}
                className={`ios-mode-btn ${profile === p ? 'active' : ''}`}
                onClick={() => setProfile(p)}
              >
                {p.charAt(0).toUpperCase() + p.slice(1)}
              </button>
            ))}
          </div>
          <button className="modal-close" onClick={modalActions.closeIosModal}>✕</button>
        </div>
        <div className="modal-body ios-modal-body">
          <div className="ios-stream-frame" ref={containerRef} style={{ touchAction: 'none' }}>
            <canvas ref={canvasRef} style={{ display: 'none', width: '100%', height: '100%', objectFit: 'fill' }} />
            <canvas ref={workerCanvasRef} style={{ display: 'none', width: '100%', height: '100%', objectFit: 'fill' }} />
            <video ref={videoRef} autoPlay muted playsInline controls style={{ display: 'none', width: '100%', height: '100%', objectFit: 'fill' }} />
            <div ref={latencyOverlayRef} className="ios-latency-overlay">{latencyText}</div>
          </div>
        </div>
      </div>
    </div>
  );
}
