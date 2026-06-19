import { useEffect, useRef, useState, type PointerEvent } from 'react';
import type { UnifiedDevice } from '../services/deviceRegistry';
import { listWorkspaceFiles, type FileEntry } from '../services/fileManager';
import { ZxTouchDeviceSdk, type CoordinateDiagnostics, type FindImageResult, type OcrResult, type PickedColor } from '../services/zxtouchSdk';

type ScreenMode = 'coordinate' | 'color' | 'region';
type ToolTab = 'interaction' | 'vision' | 'assertions';

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
  const streamWantedRef = useRef(true);
  const streamRetryTimerRef = useRef<number | undefined>(undefined);
  const dragStartRef = useRef<Point | null>(null);
  const [mode, setMode] = useState<ScreenMode>('coordinate');
  const [toolTab, setToolTab] = useState<ToolTab>('interaction');
  const [status, setStatus] = useState('Select device');
  const [streamError, setStreamError] = useState('');
  const [screenSize, setScreenSize] = useState<{ width: number; height: number } | null>(null);
  const [screenScale, setScreenScale] = useState(1);
  const [coordDiagnostics, setCoordDiagnostics] = useState<CoordinateDiagnostics | null>(null);
  const [frameSize, setFrameSize] = useState<{ width: number; height: number } | null>(null);
  const [point, setPoint] = useState<Point | null>(null);
  const [region, setRegion] = useState<Region | null>(null);
  const [pickedColor, setPickedColor] = useState<PickedColor | null>(null);
  const [templatePath, setTemplatePath] = useState('/var/mobile/Library/ZXTouch/templates/template.png');
  const [templateEntries, setTemplateEntries] = useState<FileEntry[]>([]);
  const [findResult, setFindResult] = useState<FindImageResult | null>(null);
  const [matchOptions, setMatchOptions] = useState({ acceptable: 0.9, pixelSkip: 1 });
  const [ocrOptions, setOcrOptions] = useState({ lang: 'vie', psm: 7, scaleUp: 2 });
  const [ocrText, setOcrText] = useState('');
  const [ocrResult, setOcrResult] = useState<OcrResult | null>(null);

  useEffect(() => {
    stopWorker(true);
    setPoint(null);
    setRegion(null);
    setPickedColor(null);
    setFindResult(null);
    setOcrText('');
    setOcrResult(null);
    setFrameSize(null);
    setCoordDiagnostics(null);
    setStreamError('');
    transferredRef.current = false;
    clearStreamRetry();

    if (!device || !wsBase) {
      setStatus('Select device');
      return;
    }

    let disposed = false;
    setStatus('Starting stream...');

    const loadDiagnostics = async () => {
      const sdk = new ZxTouchDeviceSdk(wsBase, device.id);
      try {
        const diagnostics = await sdk.getCoordinateDiagnostics();
        if (!disposed) applyDiagnostics(diagnostics);
      } catch (error) {
        if (!disposed) setScreenSize(null);
        addLog('debug', 'screen', error instanceof Error ? error.message : String(error));
      } finally {
        sdk.close();
      }
    };

    loadDiagnostics();
    streamWantedRef.current = isIdeVisible();
    if (streamWantedRef.current) startWorker(device.id);

    return () => {
      disposed = true;
      stopWorker(true);
      clearStreamRetry();
    };
  }, [device?.id, wsBase]);

  useEffect(() => {
    const updateStreamVisibility = (visible: boolean) => {
      streamWantedRef.current = visible;
      if (!device) return;
      if (visible) {
        startWorker(device.id);
      } else {
        stopWorker(false);
      }
    };

    const onIdeVisibility = (event: Event) => {
      const visible = Boolean((event as CustomEvent<{ visible?: boolean }>).detail?.visible);
      updateStreamVisibility(visible && document.visibilityState === 'visible');
    };
    const onDocumentVisibility = () => {
      updateStreamVisibility(isIdeVisible());
    };

    window.addEventListener('automation-ide-visibility', onIdeVisibility);
    document.addEventListener('visibilitychange', onDocumentVisibility);
    return () => {
      window.removeEventListener('automation-ide-visibility', onIdeVisibility);
      document.removeEventListener('visibilitychange', onDocumentVisibility);
    };
  }, [device?.id]);

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

  const applyDiagnostics = (diagnostics: CoordinateDiagnostics) => {
    setCoordDiagnostics(diagnostics);
    if (diagnostics.screenSize) setScreenSize(diagnostics.screenSize);
    setScreenScale(diagnostics.screenScale || 1);
    if (diagnostics.frameWidth && diagnostics.frameHeight) {
      setFrameSize({ width: diagnostics.frameWidth, height: diagnostics.frameHeight });
    }
  };

  const refreshDiagnostics = async () => {
    if (!device) return null;
    const sdk = new ZxTouchDeviceSdk(wsBase, device.id);
    try {
      const diagnostics = await sdk.getCoordinateDiagnostics();
      applyDiagnostics(diagnostics);
      addLog('debug', 'screen', `coord screen=${diagnostics.screenSize?.width}x${diagnostics.screenSize?.height} frame=${diagnostics.frameWidth}x${diagnostics.frameHeight} screenScale=${diagnostics.screenScale} coordScale=${diagnostics.coordScale}`);
      return diagnostics;
    } catch (error) {
      addLog('error', 'screen', error instanceof Error ? error.message : String(error));
      return null;
    } finally {
      sdk.close();
    }
  };

  const selectTemplate = (path: string) => {
    const name = path.split('/').filter(Boolean).pop() || path;
    setTemplatePath(`/var/mobile/Library/ZXTouch/templates/${name}`);
  };

  const startWorker = (deviceId: string) => {
    if (!streamWantedRef.current) return;
    clearStreamRetry();
    const canvas = videoCanvasRef.current;
    if (!canvas || !('Worker' in window)) {
      setStatus('Worker stream unavailable');
      return;
    }

    try {
      let worker = workerRef.current;
      if (!worker) {
        worker = new Worker(new URL('../IosH264Worker.ts', import.meta.url), { type: 'module' });
        workerRef.current = worker;
        worker.onmessage = (event) => {
        const data = event.data;
        if (data?.type === 'started') {
          clearStreamRetry();
          setStreamError('');
          setStatus('Live preview');
        }
        if (data?.type === 'frame-size') {
          setFrameSize({ width: data.width, height: data.height });
          setStatus(`Live ${data.width}x${data.height}`);
          drawOverlay();
        }
        if (data?.type === 'closed') {
          setStatus('Stream closed');
          scheduleStreamRetry();
        }
        if (data?.type === 'start-failed') {
          setStatus(`Stream failed: ${data.reason}`);
          setStreamError(data.reason || 'Stream unavailable');
          addLog('error', 'screen', data.reason);
          scheduleStreamRetry();
        }
        if (data?.type === 'decoder-error') {
          setStreamError(data.error || 'Decoder unavailable');
          addLog('error', 'screen', data.error);
          scheduleStreamRetry();
        }
        };
      }

      if (!transferredRef.current) {
        if (!('transferControlToOffscreen' in canvas)) {
          setStatus('Worker stream unavailable');
          return;
        }
        const offscreen = canvas.transferControlToOffscreen();
        transferredRef.current = true;
        worker.postMessage({
          type: 'start',
          url: `${wsBase}/ios/${encodeURIComponent(deviceId)}/h264-worker`,
          canvas: offscreen,
        }, [offscreen]);
        return;
      }

      worker.postMessage({
        type: 'start',
        url: `${wsBase}/ios/${encodeURIComponent(deviceId)}/h264-worker`,
      });
    } catch (error) {
      setStatus('Stream unavailable');
      addLog('error', 'screen', error instanceof Error ? error.message : String(error));
    }
  };

  const stopWorker = (terminate = true) => {
    clearStreamRetry();
    try {
      workerRef.current?.postMessage({ type: 'stop' });
    } catch {}
    if (terminate) {
      try {
        workerRef.current?.terminate();
      } catch {}
      workerRef.current = null;
    }
  };

  const clearStreamRetry = () => {
    if (streamRetryTimerRef.current !== undefined) {
      window.clearTimeout(streamRetryTimerRef.current);
      streamRetryTimerRef.current = undefined;
    }
  };

  const scheduleStreamRetry = () => {
    if (!streamWantedRef.current || !device) return;
    if (streamRetryTimerRef.current !== undefined) return;
    streamRetryTimerRef.current = window.setTimeout(() => {
      streamRetryTimerRef.current = undefined;
      if (streamWantedRef.current && device) startWorker(device.id);
    }, 600);
  };

  const mapEventPoint = (event: PointerEvent<HTMLCanvasElement>): Point | null => {
    const canvas = overlayCanvasRef.current;
    if (!canvas) return null;
    const rect = canvas.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return null;
    const size = screenSize || { width: 375, height: 667 };
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

  const testFindImage = async (pathOverride?: string) => {
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
      const path = pathOverride || templatePath;
      const result = await sdk.findImage(path, {
        region: [region.x, region.y, region.width, region.height],
        acceptable: matchOptions.acceptable,
        scaleMin: 1,
        scaleMax: 1,
        pixelSkip: matchOptions.pixelSkip,
      });
      setFindResult(result);
      setStatus(`${result.found ? 'Match' : 'Best'} ${result.score.toFixed(3)}`);
      addLog('info', 'screen', `findImage path=${path} found=${result.found} score=${result.score.toFixed(3)} center=${result.centerX},${result.centerY} region=[${region.x},${region.y},${region.width},${region.height}] nativeRegion=[${result.native?.region.join(',')}] coordScale=${result.native?.coordScale}`);
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
          acceptable: matchOptions.acceptable,
          scaleMin: 1,
          scaleMax: 1,
          pixelSkip: matchOptions.pixelSkip,
        });
        setFindResult(result);
        setStatus(`Captured ${result.found ? 'match' : 'best'} ${result.score.toFixed(3)}`);
        addLog('info', 'screen', `captured template found=${result.found} score=${result.score.toFixed(3)} center=${result.centerX},${result.centerY} nativeRegion=[${result.native?.region.join(',')}] coordScale=${result.native?.coordScale}`);
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
    await saveTemplateRegion(false);
  };

  const saveAndTestTemplate = async () => {
    const savedPath = await saveTemplateRegion(true);
    if (savedPath) await testFindImage(savedPath);
  };

  const saveTemplateRegion = async (quietExistingName: boolean) => {
    if (!device) {
      addLog('warn', 'screen', 'Select an online iOS device first.');
      return null;
    }
    if (!region || region.width <= 0 || region.height <= 0) {
      addLog('warn', 'screen', 'Select a region first.');
      return null;
    }
    const rawName = quietExistingName
      ? (templatePath.split('/').pop() || 'template.png')
      : window.prompt('Template file name', templatePath.split('/').pop() || 'template.png');
    if (!rawName) return null;
    const fileName = rawName.endsWith('.png') ? rawName : `${rawName}.png`;
    const path = `/var/mobile/Library/ZXTouch/templates/${fileName}`;
    const sdk = new ZxTouchDeviceSdk(wsBase, device.id);
    try {
      setStatus('Saving template...');
      const savedPath = await sdk.screenshot(path, [region.x, region.y, region.width, region.height]);
      setTemplatePath(savedPath || path);
      setStatus('Template saved');
      addLog('info', 'screen', `saved template ${savedPath || path}`);
      return savedPath || path;
    } catch (error) {
      setStatus('Save template failed');
      addLog('error', 'screen', error instanceof Error ? error.message : String(error));
      return null;
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
      setOcrResult(result);
      setStatus(`OCR ${result.confidence !== undefined ? `conf ${result.confidence.toFixed(1)}` : 'complete'}`);
      addLog('info', 'screen', `ocr text=${JSON.stringify(result.text)} conf=${formatMaybeNumber(result.confidence)} region=[${region.x},${region.y},${region.width},${region.height}] nativeRegion=[${result.diagnostics?.nativeRegion.join(',')}] frame=${result.diagnostics?.frame.width}x${result.diagnostics?.frame.height} coordScale=${result.diagnostics?.coordScale} totalMs=${formatMaybeNumber(result.totalMs)}`);
    } catch (error) {
      setOcrText('');
      setOcrResult(null);
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

  const swipeSnippet = () => {
    if (region && region.width > 0 && region.height > 0) {
      return `await device.swipe(${region.x}, ${region.y}, ${region.x + region.width}, ${region.y + region.height}, 300);`;
    }
    const x = point?.x ?? Math.round((screenSize?.width ?? 375) / 2);
    const y = point?.y ?? Math.round((screenSize?.height ?? 667) / 2);
    return `await device.swipe(${x}, ${y}, ${x + 120}, ${y}, 300);`;
  };

  const scrollUpSnippet = () => {
    if (region && region.width > 0 && region.height > 0) {
      const x = Math.round(region.x + region.width / 2);
      return `await device.swipe(${x}, ${region.y + region.height - 8}, ${x}, ${region.y + 8}, 500);`;
    }
    const width = screenSize?.width ?? 375;
    const height = screenSize?.height ?? 667;
    const x = point?.x ?? Math.round(width / 2);
    return `await device.swipe(${x}, ${Math.round(height * 0.75)}, ${x}, ${Math.round(height * 0.25)}, 500);`;
  };

  return (
    <div className="ide-screen-panel">
      <div className="ide-tools-header">
        <div className="panel-title">Device Tools</div>
        <div className="ide-tools-header-actions">
          <button type="button" onClick={refreshDiagnostics}>Diag</button>
          <span>{status}</span>
        </div>
      </div>
      <div className="ide-tool-tabs">
        <button type="button" className={toolTab === 'interaction' ? 'active' : ''} onClick={() => setToolTab('interaction')}>Interaction</button>
        <button type="button" className={toolTab === 'vision' ? 'active' : ''} onClick={() => setToolTab('vision')}>Vision</button>
        <button type="button" className={toolTab === 'assertions' ? 'active' : ''} onClick={() => setToolTab('assertions')}>Assertions</button>
      </div>

      <div className="ide-tools-body">
        <div className="ide-tools-sidebar">
          <div className="ide-mode-selector">
            <button type="button" className={mode === 'coordinate' ? 'active' : ''} onClick={() => setMode('coordinate')}>Pick point</button>
            <button type="button" className={mode === 'color' ? 'active' : ''} onClick={() => setMode('color')}>Pick color</button>
            <button type="button" className={mode === 'region' ? 'active' : ''} onClick={() => setMode('region')}>Select region</button>
          </div>

          {toolTab === 'interaction' ? (
            <div className="ide-tool-button-grid">
              <button type="button" disabled={!point} onClick={() => point && insertSnippet(`await device.tap(${point.x}, ${point.y});`)}><span>Tap</span></button>
              <button type="button" disabled={!point} onClick={() => point && insertSnippet(`await device.tap(${point.x}, ${point.y}, 650);`)}><span>Long Press</span></button>
              <button type="button" onClick={() => insertSnippet(swipeSnippet())}><span>Swipe</span></button>
              <button type="button" onClick={() => insertSnippet(scrollUpSnippet())}><span>Scroll up</span></button>
              <button type="button" onClick={() => insertSnippet('// input text via raw zxtouch task if needed') }><span>Input Text</span></button>
              <button type="button" onClick={() => insertSnippet('const response = await device.request(25, 1);\nlog(response);')}><span>Raw Task</span></button>
            </div>
          ) : null}

          {toolTab === 'vision' ? (
            <>
              <div className="ide-vision-flow">
                <div className="ide-flow-title">Template</div>
                <div className="ide-flow-actions">
                  <button type="button" disabled={!region} onClick={saveTemplateFromRegion}>Save</button>
                  <button type="button" disabled={!region} onClick={saveAndTestTemplate}>Save + Test</button>
                  <button type="button" disabled={!region} onClick={() => testFindImage()}>Test path</button>
                  <button type="button" disabled={!findResult?.found} onClick={() => findResult?.found && insertSnippet(`await device.tap(${findResult.centerX}, ${findResult.centerY});`)}>Tap match</button>
                </div>
                <div className="ide-flow-title">Insert</div>
                <div className="ide-flow-actions">
                  <button type="button" disabled={!point} onClick={() => point && insertSnippet(`const color = await device.pickColor(${point.x}, ${point.y});\nlog(color);`)}>Color</button>
                  <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const found = await device.findImage("${templatePath}", {\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  acceptable: ${matchOptions.acceptable},\n  scaleMin: 1,\n  scaleMax: 1,\n  pixelSkip: ${matchOptions.pixelSkip}\n});\nif (found.found) await device.tap(found.centerX, found.centerY);\nlog(found);`)}>Find+tap</button>
                  <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const text = await device.ocr({\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  lang: "${ocrOptions.lang}",\n  psm: ${ocrOptions.psm},\n  scaleUp: ${ocrOptions.scaleUp}\n});\nlog(text);`)}>OCR</button>
                  <button type="button" disabled={!region} onClick={testCapturedTemplate}>Test captured</button>
                </div>
              </div>
              <div className="ide-template-test compact">
                <div className="ide-template-header">
                  <span>Image template</span>
                  <button type="button" onClick={refreshTemplates}>Refresh</button>
                </div>
                {templateEntries.length > 0 ? (
                  <select className="ide-template-select" value="" onChange={(event) => event.target.value && selectTemplate(event.target.value)}>
                    <option value="">Choose template</option>
                    {templateEntries.map((entry) => (
                      <option key={entry.path} value={entry.path}>{entry.name}</option>
                    ))}
                  </select>
                ) : null}
                <label>
                  Template path
                  <input value={templatePath} onChange={(event) => setTemplatePath(event.target.value)} />
                </label>
                <div className="ide-match-compact">
                  <label>Accept<input type="number" step="0.01" min="0" max="1" value={matchOptions.acceptable} onChange={(event) => setMatchOptions((current) => ({ ...current, acceptable: numberValue(event.target.value) }))} /></label>
                  <label>Skip<input type="number" min="0" value={matchOptions.pixelSkip} onChange={(event) => setMatchOptions((current) => ({ ...current, pixelSkip: numberValue(event.target.value) }))} /></label>
                </div>
                <div className="ide-template-actions">
                  <button type="button" disabled={!region} onClick={() => testFindImage()}>Test</button>
                  <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const found = await device.findImage("${templatePath}", {\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  acceptable: ${matchOptions.acceptable},\n  scaleMin: 1,\n  scaleMax: 1,\n  pixelSkip: ${matchOptions.pixelSkip}\n});\nif (found.found) await device.tap(found.centerX, found.centerY);\nlog(found);`)}>Find+tap</button>
                </div>
                {findResult ? (
                  <div className="ide-result-card">
                    <span>{findResult.found ? 'Found' : 'Best only'} score {findResult.score.toFixed(3)}</span>
                    <span>Center {findResult.centerX},{findResult.centerY}</span>
                    <span>Box [{findResult.x},{findResult.y},{findResult.width},{findResult.height}]</span>
                    <span>Native [{findResult.native?.region.join(',') || '-'}]</span>
                  </div>
                ) : null}
              </div>
              <div className="ide-template-test compact">
                <div className="ide-template-header">
                  <span>OCR</span>
                  <button type="button" disabled={!region} onClick={testOcr}>Test</button>
                </div>
                <div className="ide-ocr-compact">
                  <label>Lang<input value={ocrOptions.lang} onChange={(event) => setOcrOptions((current) => ({ ...current, lang: event.target.value }))} /></label>
                  <label>PSM<input type="number" value={ocrOptions.psm} onChange={(event) => setOcrOptions((current) => ({ ...current, psm: numberValue(event.target.value) }))} /></label>
                  <label>Scale<input type="number" value={ocrOptions.scaleUp} onChange={(event) => setOcrOptions((current) => ({ ...current, scaleUp: numberValue(event.target.value) }))} /></label>
                </div>
                <div className="ide-template-actions">
                  <button type="button" disabled={!region} onClick={testOcr}>Test</button>
                  <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const text = await device.ocr({\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  lang: "${ocrOptions.lang}",\n  psm: ${ocrOptions.psm},\n  scaleUp: ${ocrOptions.scaleUp}\n});\nlog(text);`)}>Insert</button>
                </div>
                {ocrResult ? (
                  <div className="ide-result-card">
                    <span>Conf {formatMaybeNumber(ocrResult.confidence)}</span>
                    <span>Total {formatMaybeNumber(ocrResult.totalMs)}ms</span>
                    <span>Native [{ocrResult.diagnostics?.nativeRegion.join(',') || '-'}]</span>
                  </div>
                ) : null}
              </div>
            </>
          ) : null}

          {toolTab === 'assertions' ? (
            <div className="ide-tool-button-grid">
              <button type="button" disabled={!pickedColor || !point} onClick={() => point && pickedColor && insertSnippet(`const ok = await device.colorEquals(${point.x}, ${point.y}, "${pickedColor.hex}", 10);\nassert(ok, "color mismatch");`)}><span>Assert color</span></button>
              <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const found = await device.findImage("${templatePath}", {\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  acceptable: ${matchOptions.acceptable},\n  scaleMin: 1,\n  scaleMax: 1,\n  pixelSkip: ${matchOptions.pixelSkip}\n});\nassert(found.found, "image not found");`)}><span>Assert image</span></button>
              <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const text = await device.ocr({\n  region: [${region.x}, ${region.y}, ${region.width}, ${region.height}],\n  lang: "${ocrOptions.lang}",\n  psm: ${ocrOptions.psm},\n  scaleUp: ${ocrOptions.scaleUp}\n});\nassert(text.text.length > 0, "OCR empty");\nlog(text);`)}><span>Assert OCR</span></button>
              <button type="button" disabled={!region} onClick={() => region && insertSnippet(`const region = [${region.x}, ${region.y}, ${region.width}, ${region.height}];`)}><span>Insert region</span></button>
            </div>
          ) : null}

          <div className="ide-screen-readout">
            <span>{screenSize ? `Screen ${screenSize.width}x${screenSize.height}@${screenScale}` : 'Screen unknown'}</span>
            <span>{frameSize ? `Frame ${frameSize.width}x${frameSize.height}` : 'Frame unknown'}</span>
            <span>{coordDiagnostics ? `Coord scale ${coordDiagnostics.coordScale}` : 'Coord scale unknown'}</span>
            <span>{coordDiagnostics?.frameScale ? `Frame scale ${coordDiagnostics.frameScale}` : 'Frame scale unknown'}</span>
            <span>{point ? `Point ${point.x},${point.y}` : 'No point'}</span>
            <span>{pickedColor ? pickedColor.hex : 'No color'}</span>
            <span>{findResult ? `Image ${findResult.found ? 'found' : 'best'} ${findResult.score.toFixed(3)}` : 'No match'}</span>
            <span>{findResult?.native ? `Image native [${findResult.native.region.join(',')}]` : 'No image native'}</span>
            <span>{ocrResult ? `OCR conf ${formatMaybeNumber(ocrResult.confidence)}` : 'No OCR conf'}</span>
            <span>{ocrResult?.diagnostics ? `OCR native [${ocrResult.diagnostics.nativeRegion.join(',')}]` : 'No OCR native'}</span>
            <span>{ocrResult?.totalMs !== undefined ? `OCR total ${formatMaybeNumber(ocrResult.totalMs)}ms` : 'No OCR timing'}</span>
            <span>{region ? `Region [${region.x},${region.y},${region.width},${region.height}]` : 'No region'}</span>
          </div>
        </div>

        <div className="ide-screen-stage">
          <div className="ide-screen-frame" style={{ aspectRatio: screenSize ? `${screenSize.width} / ${screenSize.height}` : '9 / 16' }}>
            <canvas key={device?.id || 'no-device'} ref={videoCanvasRef} className="ide-screen-video" />
            {streamError ? <div className="ide-screen-fallback">{streamError}</div> : null}
            <canvas
              ref={overlayCanvasRef}
              className="ide-screen-overlay"
              onPointerDown={handlePointerDown}
              onPointerMove={handlePointerMove}
              onPointerUp={handlePointerUp}
              onPointerCancel={() => { dragStartRef.current = null; }}
            />
          </div>
          {ocrText ? <div className="ide-ocr-result">{ocrText}</div> : null}
        </div>
      </div>
    </div>
  );
}

function numberValue(value: string) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatMaybeNumber(value: number | undefined) {
  return value === undefined ? '-' : value.toFixed(Number.isInteger(value) ? 0 : 2);
}

function pointsToRegion(a: Point, b: Point): Region {
  return {
    x: Math.min(a.x, b.x),
    y: Math.min(a.y, b.y),
    width: Math.abs(a.x - b.x),
    height: Math.abs(a.y - b.y),
  };
}

function isIdeVisible() {
  const pane = document.getElementById('automation-ide-pane');
  return document.visibilityState === 'visible' && (!pane || pane.style.display !== 'none');
}
