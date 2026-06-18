import { useEffect, useRef, useState, type PointerEvent } from 'react';
import type { UnifiedDevice } from '../services/deviceRegistry';
import { listWorkspaceFiles, type FileEntry } from '../services/fileManager';
import { ZxTouchDeviceSdk, type FindImageResult, type PickedColor } from '../services/zxtouchSdk';

type ScreenMode = 'coordinate' | 'color' | 'region';

type Point = { x: number; y: number };
type Region = { x: number; y: number; width: number; height: number };

type Props = {
  device?: UnifiedDevice;
  httpBase: string;
  wsBase: string;
  insertSnippet: (snippet: string) => void;
  addLog: (level: 'info' | 'warn' | 'error' | 'debug', source: string, message: unknown) => void;
};

export function IdeScreenPanel({ device, httpBase, wsBase, insertSnippet, addLog }: Props) {
  const videoCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const overlayCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const workerRef = useRef<Worker | null>(null);
  const transferredRef = useRef(false);
  const dragStartRef = useRef<Point | null>(null);
  const [mode, setMode] = useState<ScreenMode>('coordinate');
  const [status, setStatus] = useState('Select device');
  const [screenSize, setScreenSize] = useState<{ width: number; height: number } | null>(null);
  const [frameSize, setFrameSize] = useState<{ width: number; height: number } | null>(null);
  const [point, setPoint] = useState<Point | null>(null);
  const [region, setRegion] = useState<Region | null>(null);
  const [pickedColor, setPickedColor] = useState<PickedColor | null>(null);
  const [templatePath, setTemplatePath] = useState('/var/mobile/Library/ZXTouch/templates/template.png');
  const [templateEntries, setTemplateEntries] = useState<FileEntry[]>([]);
  const [findResult, setFindResult] = useState<FindImageResult | null>(null);
  const [ocrOptions, setOcrOptions] = useState({ lang: 'vie', psm: 7, scaleUp: 2 });
  const [ocrText, setOcrText] = useState('');

  useEffect(() => {
    stopWorker();
    setPoint(null);
    setRegion(null);
    setPickedColor(null);
    setFindResult(null);
    setOcrText('');
    setFrameSize(null);
    transferredRef.current = false;

    if (!device || !wsBase) {
      setStatus('Select device');
      return;
    }

    let disposed = false;
    setStatus('Starting stream...');

    const loadScreenSize = async () => {
      const sdk = new ZxTouchDeviceSdk(wsBase, device.id);
      try {
        const size = await sdk.getScreenSize();
        if (!disposed && size) setScreenSize(size);
      } catch {
        if (!disposed) setScreenSize(null);
      } finally {
        sdk.close();
      }
    };

    loadScreenSize();
    startWorker(device.id);

    return () => {
      disposed = true;
      stopWorker();
    };
  }, [device?.id, wsBase]);

  useEffect(() => {
    drawOverlay();
  }, [point, region, pickedColor, findResult, mode, screenSize]);

  useEffect(() => {
    refreshTemplates();
  }, [httpBase]);

  const refreshTemplates = async () => {
    try {
      const listing = await listWorkspaceFiles(httpBase, 'templates');
      setTemplateEntries(listing.entries.filter((entry) => entry.kind === 'file'));
    } catch (error) {
      addLog('debug', 'screen', error instanceof Error ? error.message : String(error));
    }
  };

  const selectTemplate = (path: string) => {
    const name = path.split('/').filter(Boolean).pop() || path;
    setTemplatePath(`/var/mobile/Library/ZXTouch/templates/${name}`);
  };

  const startWorker = (deviceId: string) => {
    const canvas = videoCanvasRef.current;
    if (!canvas || !('transferControlToOffscreen' in canvas) || !('Worker' in window)) {
      setStatus('Worker stream unavailable');
      return;
    }

    try {
      const worker = new Worker(new URL('../IosH264Worker.ts', import.meta.url), { type: 'module' });
      workerRef.current = worker;
      worker.onmessage = (event) => {
        const data = event.data;
        if (data?.type === 'started') setStatus('Live preview');
        if (data?.type === 'frame-size') {
          setFrameSize({ width: data.width, height: data.height });
          setStatus(`Live ${data.width}x${data.height}`);
          drawOverlay();
        }
        if (data?.type === 'closed') setStatus('Stream closed');
        if (data?.type === 'start-failed') {
          setStatus(`Stream failed: ${data.reason}`);
          addLog('error', 'screen', data.reason);
        }
        if (data?.type === 'decoder-error') addLog('error', 'screen', data.error);
      };

      const offscreen = canvas.transferControlToOffscreen();
      transferredRef.current = true;
      worker.postMessage({
        type: 'start',
        url: `${wsBase}/ios/${encodeURIComponent(deviceId)}/h264-worker`,
        canvas: offscreen,
      }, [offscreen]);
    } catch (error) {
      setStatus('Stream unavailable');
      addLog('error', 'screen', error instanceof Error ? error.message : String(error));
    }
  };

  const stopWorker = () => {
    try {
      workerRef.current?.postMessage({ type: 'stop' });
    } catch {}
    try {
      workerRef.current?.terminate();
    } catch {}
    workerRef.current = null;
  };

  const mapEventPoint = (event: PointerEvent<HTMLCanvasElement>): Point | null => {
    const canvas = overlayCanvasRef.current;
    if (!canvas) return null;
    const rect = canvas.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return null;
    const size = screenSize || { width: canvas.width || 375, height: canvas.height || 667 };
    return {
      x: Math.round(((event.clientX - rect.left) / rect.width) * size.width),
      y: Math.round(((event.clientY - rect.top) / rect.height) * size.height),
    };
  };

  const handlePointerDown = (event: PointerEvent<HTMLCanvasElement>) => {
    const nextPoint = mapEventPoint(event);
    if (!nextPoint) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    dragStartRef.current = nextPoint;
    setPoint(nextPoint);
    if (mode === 'region') setRegion({ x: nextPoint.x, y: nextPoint.y, width: 0, height: 0 });
  };

  const handlePointerMove = (event: PointerEvent<HTMLCanvasElement>) => {
    if (mode !== 'region' || !dragStartRef.current) return;
    const current = mapEventPoint(event);
    if (!current) return;
    setRegion(pointsToRegion(dragStartRef.current, current));
  };

  const handlePointerUp = async (event: PointerEvent<HTMLCanvasElement>) => {
    const current = mapEventPoint(event);
    try {
      event.currentTarget.releasePointerCapture(event.pointerId);
    } catch {}

    const start = dragStartRef.current;
    dragStartRef.current = null;
    if (!current) return;

    if (mode === 'coordinate') {
      setPoint(current);
      addLog('info', 'screen', `point ${current.x},${current.y}`);
    } else if (mode === 'color') {
      setPoint(current);
      await pickColorAt(current);
    } else if (mode === 'region' && start) {
      const nextRegion = pointsToRegion(start, current);
      setRegion(nextRegion);
      setFindResult(null);
      setOcrText('');
      addLog('info', 'screen', `region [${nextRegion.x}, ${nextRegion.y}, ${nextRegion.width}, ${nextRegion.height}]`);
    }
  };

  const pickColorAt = async (target: Point) => {
    if (!device) return;
    const sdk = new ZxTouchDeviceSdk(wsBase, device.id);
    try {
      const color = await sdk.pickColor(target.x, target.y);
      setPickedColor(color);
      addLog('info', 'screen', `color ${target.x},${target.y} = ${color.hex}`);
    } catch (error) {
      addLog('error', 'screen', error instanceof Error ? error.message : String(error));
    } finally {
      sdk.close();
    }
  };

  const testFindImage = async () => {
    if (!device) {
      addLog('warn', 'screen', 'Select an online iOS device first.');
      return;
    }
    if (!region || region.width <= 0 || region.height <= 0) {
      addLog('warn', 'screen', 'Select a region first.');
      return;
    }
    const sdk = new ZxTouchDeviceSdk(wsBase, device.id);
    try {
      setStatus('Testing image...');
      const result = await sdk.findImage(templatePath, {
        region: [region.x, region.y, region.width, region.height],
        acceptable: 0.8,
        pixelSkip: 1,
      });
      setFindResult(result);
      setStatus(`Match ${result.score.toFixed(3)}`);
      addLog('info', 'screen', `findImage score=${result.score.toFixed(3)} center=${result.centerX},${result.centerY}`);
    } catch (error) {
      setFindResult(null);
      setStatus('Image test failed');
      addLog('error', 'screen', error instanceof Error ? error.message : String(error));
    } finally {
      sdk.close();
    }
  };

  const testCapturedTemplate = async () => {
    if (!device) {
      addLog('warn', 'screen', 'Select an online iOS device first.');
      return;
    }
    if (!region || region.width <= 0 || region.height <= 0) {
      addLog('warn', 'screen', 'Select a region first.');
      return;
    }
    const sdk = new ZxTouchDeviceSdk(wsBase, device.id);
    try {
      setStatus('Capturing template...');
      const template = await sdk.captureImage([region.x, region.y, region.width, region.height]);
      try {
        const result = await sdk.findImageObject(template, {
          region: [0, 0, 0, 0],
          acceptable: 0.8,
          pixelSkip: 1,
        });
        setFindResult(result);
        setStatus(`Captured match ${result.score.toFixed(3)}`);
        addLog('info', 'screen', `captured template score=${result.score.toFixed(3)} center=${result.centerX},${result.centerY}`);
      } finally {
        await sdk.releaseImage(template).catch(() => {});
      }
    } catch (error) {
      setFindResult(null);
      setStatus('Captured template test failed');
      addLog('error', 'screen', error instanceof Error ? error.message : String(error));
    } finally {
      sdk.close();
    }
  };

  const saveTemplateFromRegion = async () => {
    if (!device) {
      addLog('warn', 'screen', 'Select an online iOS device first.');
      return;
    }
    if (!region || region.width <= 0 || region.height <= 0) {
      addLog('warn', 'screen', 'Select a region first.');
      return;
    }
    const rawName = window.prompt('Template file name', templatePath.split('/').pop() || 'template.png');
    if (!rawName) return;
    const fileName = rawName.endsWith('.png') ? rawName : `${rawName}.png`;
    const path = `/var/mobile/Library/ZXTouch/templates/${fileName}`;
    const sdk = new ZxTouchDeviceSdk(wsBase, device.id);
    try {
      setStatus('Saving template...');
      const savedPath = await sdk.screenshot(path, [region.x, region.y, region.width, region.height]);
      setTemplatePath(savedPath || path);
      setStatus('Template saved');
      addLog('info', 'screen', `saved template ${savedPath || path}`);
    } catch (error) {
      setStatus('Save template failed');
      addLog('error', 'screen', error instanceof Error ? error.message : String(error));
    } finally {
      sdk.close();
    }
  };

  const testOcr = async () => {
    if (!device) {
      addLog('warn', 'screen', 'Select an online iOS device first.');
      return;
    }
    if (!region || region.width <= 0 || region.height <= 0) {
      addLog('warn', 'screen', 'Select a region first.');
      return;
    }
    const sdk = new ZxTouchDeviceSdk(wsBase, device.id);
    try {
      setStatus('Running OCR...');
      const result = await sdk.ocr({
        region: [region.x, region.y, region.width, region.height],
        lang: ocrOptions.lang,
        psm: ocrOptions.psm,
        scaleUp: ocrOptions.scaleUp,
      });
      setOcrText(result.text);
      setStatus('OCR complete');
      addLog('info', 'screen', `ocr ${JSON.stringify(result.text)}`);
    } catch (error) {
      setOcrText('');
      setStatus('OCR failed');
      addLog('error', 'screen', error instanceof Error ? error.message : String(error));
    } finally {
      sdk.close();
    }
  };

  const drawOverlay = () => {
    const canvas = overlayCanvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const width = Math.max(1, Math.round(rect.width * dpr));
    const height = Math.max(1, Math.round(rect.height * dpr));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, width, height);
    ctx.save();
    ctx.scale(dpr, dpr);

    const cssWidth = rect.width;
    const cssHeight = rect.height;
    const size = screenSize || { width: 375, height: 667 };
    const toCanvasX = (x: number) => (x / size.width) * cssWidth;
    const toCanvasY = (y: number) => (y / size.height) * cssHeight;

    if (point) {
      const x = toCanvasX(point.x);
      const y = toCanvasY(point.y);
      ctx.strokeStyle = pickedColor?.hex || '#38bdf8';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(x - 12, y);
      ctx.lineTo(x + 12, y);
      ctx.moveTo(x, y - 12);
      ctx.lineTo(x, y + 12);
      ctx.stroke();
      ctx.fillStyle = '#0f172a';
      ctx.fillRect(x + 8, y + 8, 84, 22);
      ctx.fillStyle = '#ffffff';
      ctx.font = '12px JetBrains Mono, monospace';
      ctx.fillText(`${point.x},${point.y}`, x + 13, y + 23);
    }

    if (region && region.width > 0 && region.height > 0) {
      const x = toCanvasX(region.x);
      const y = toCanvasY(region.y);
      const w = toCanvasX(region.x + region.width) - x;
      const h = toCanvasY(region.y + region.height) - y;
      ctx.fillStyle = 'rgba(59, 130, 246, 0.16)';
      ctx.strokeStyle = '#3b82f6';
      ctx.lineWidth = 2;
      ctx.fillRect(x, y, w, h);
      ctx.strokeRect(x, y, w, h);
      ctx.fillStyle = '#1d4ed8';
      ctx.fillRect(x, Math.max(0, y - 22), 140, 20);
      ctx.fillStyle = '#ffffff';
      ctx.font = '12px JetBrains Mono, monospace';
      ctx.fillText(`${region.x},${region.y},${region.width},${region.height}`, x + 6, Math.max(14, y - 7));
    }

    if (findResult && findResult.width > 0 && findResult.height > 0) {
      const x = toCanvasX(findResult.x);
      const y = toCanvasY(findResult.y);
      const w = toCanvasX(findResult.x + findResult.width) - x;
      const h = toCanvasY(findResult.y + findResult.height) - y;
      ctx.strokeStyle = '#22c55e';
      ctx.lineWidth = 2;
      ctx.strokeRect(x, y, w, h);
      ctx.fillStyle = '#166534';
      ctx.fillRect(x, y + h + 2, 92, 20);
      ctx.fillStyle = '#ffffff';
      ctx.font = '12px JetBrains Mono, monospace';
      ctx.fillText(`score ${findResult.score.toFixed(2)}`, x + 6, y + h + 16);
    }

    ctx.restore();
  };

  return (
    <div className="ide-screen-panel">
      <div className="ide-screen-toolbar">
        <select value={mode} onChange={(event) => setMode(event.target.value as ScreenMode)}>
          <option value="coordinate">Coordinate</option>
          <option value="color">Color</option>
          <option value="region">Region</option>
        </select>
        <span>{status}</span>
      </div>
      <div className="ide-screen-frame" style={{ aspectRatio: screenSize ? `${screenSize.width} / ${screenSize.height}` : '9 / 16' }}>
        <canvas key={device?.id || 'no-device'} ref={videoCanvasRef} className="ide-screen-video" />
        <canvas
          ref={overlayCanvasRef}
          className="ide-screen-overlay"
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onPointerCancel={() => { dragStartRef.current = null; }}
        />
      </div>
      <div className="ide-screen-actions">
        <button type="button" disabled={!point} onClick={() => point && insertSnippet(`await device.tap(${point.x}, ${point.y});`)}>Insert tap</button>
        <button type="button" disabled={!point} onClick={() => point && insertSnippet(`const color = await device.pickColor(${point.x}, ${point.y});\nlog(color);`)}>Insert color</button>
        <button type="button" disabled={!pickedColor || !point} onClick={() => point && pickedColor && insertSnippet(`const ok = await device.colorEquals(${point.x}, ${point.y}, "${pickedColor.hex}", 10);`)}>Insert equals</button>
        <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const region = [${region.x}, ${region.y}, ${region.width}, ${region.height}];`)}>Insert region</button>
        <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const found = await device.findImage("/var/mobile/Library/ZXTouch/templates/template.png", {\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  acceptable: 0.8,\n  pixelSkip: 1\n});\nlog(found);`)}>Insert findImage</button>
        <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const text = await device.ocr({\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  lang: "${ocrOptions.lang}",\n  psm: ${ocrOptions.psm},\n  scaleUp: ${ocrOptions.scaleUp}\n});\nlog(text);`)}>Insert OCR</button>
        <button type="button" disabled={!region} onClick={testCapturedTemplate}>Test captured</button>
        <button type="button" disabled={!region} onClick={saveTemplateFromRegion}>Save template</button>
        <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const template = await device.captureImage([${region.x}, ${region.y}, ${region.width}, ${region.height}]);\ntry {\n  const found = await device.findImageObject(template, {\n    region: [0, 0, 0, 0],\n    acceptable: 0.8,\n    pixelSkip: 1\n  });\n  log(found);\n} finally {\n  await device.releaseImage(template);\n}`)}>Insert capture template</button>
        <button type="button" disabled={!region} onClick={() => region && insertSnippet(`async function waitFindCapturedTemplate(timeoutMs = 5000) {\n  const template = await device.captureImage([${region.x}, ${region.y}, ${region.width}, ${region.height}]);\n  try {\n    const started = Date.now();\n    while (Date.now() - started < timeoutMs) {\n      const found = await device.findImageObject(template, {\n        region: [0, 0, 0, 0],\n        acceptable: 0.8,\n        pixelSkip: 1\n      });\n      if (found.score >= 0.8) return found;\n      await sleep(200);\n    }\n    return null;\n  } finally {\n    await device.releaseImage(template);\n  }\n}\n\nconst found = await waitFindCapturedTemplate();\nlog(found);`)}>Insert wait captured</button>
      </div>
      <div className="ide-template-test">
        <div className="ide-template-header">
          <span>Image template</span>
          <button type="button" onClick={refreshTemplates}>Refresh</button>
        </div>
        {templateEntries.length > 0 ? (
          <select className="ide-template-select" value="" onChange={(event) => event.target.value && selectTemplate(event.target.value)}>
            <option value="">Choose workspace template</option>
            {templateEntries.map((entry) => (
              <option key={entry.path} value={entry.path}>{entry.name}</option>
            ))}
          </select>
        ) : null}
        <label>
          Template path
          <input value={templatePath} onChange={(event) => setTemplatePath(event.target.value)} />
        </label>
        <div className="ide-template-actions">
          <button type="button" disabled={!region} onClick={testFindImage}>Test findImage</button>
          <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const found = await device.findImage("${templatePath}", {\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  acceptable: 0.8,\n  pixelSkip: 1\n});\nlog(found);`)}>Insert with path</button>
        </div>
      </div>
      <div className="ide-template-test">
        <div className="ide-ocr-grid">
          <label>
            Lang
            <input value={ocrOptions.lang} onChange={(event) => setOcrOptions((current) => ({ ...current, lang: event.target.value }))} />
          </label>
          <label>
            PSM
            <input type="number" value={ocrOptions.psm} onChange={(event) => setOcrOptions((current) => ({ ...current, psm: numberValue(event.target.value) }))} />
          </label>
          <label>
            Scale
            <input type="number" value={ocrOptions.scaleUp} onChange={(event) => setOcrOptions((current) => ({ ...current, scaleUp: numberValue(event.target.value) }))} />
          </label>
        </div>
        <div className="ide-template-actions">
          <button type="button" disabled={!region} onClick={testOcr}>Test OCR</button>
          <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const text = await device.ocr({\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  lang: "${ocrOptions.lang}",\n  psm: ${ocrOptions.psm},\n  scaleUp: ${ocrOptions.scaleUp}\n});\nlog(text);`)}>Insert OCR</button>
        </div>
        {ocrText ? <div className="ide-ocr-result">{ocrText}</div> : null}
      </div>
      <div className="ide-screen-readout">
        <span>{screenSize ? `Screen ${screenSize.width}x${screenSize.height}` : 'Screen size unknown'}</span>
        <span>{frameSize ? `Frame ${frameSize.width}x${frameSize.height}` : 'Frame unknown'}</span>
        <span>{point ? `Point ${point.x},${point.y}` : 'No point'}</span>
        <span>{pickedColor ? pickedColor.hex : 'No color'}</span>
        <span>{findResult ? `Score ${findResult.score.toFixed(3)}` : 'No match'}</span>
        <span>{ocrText ? `OCR ${ocrText.slice(0, 18)}` : 'No OCR'}</span>
        <span>{region ? `Region [${region.x},${region.y},${region.width},${region.height}]` : 'No region'}</span>
      </div>
    </div>
  );
}

function numberValue(value: string) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function pointsToRegion(a: Point, b: Point): Region {
  return {
    x: Math.min(a.x, b.x),
    y: Math.min(a.y, b.y),
    width: Math.abs(a.x - b.x),
    height: Math.abs(a.y - b.y),
  };
}
