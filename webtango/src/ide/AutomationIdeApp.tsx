import { loader } from '@monaco-editor/react';
import * as monaco from 'monaco-editor/esm/vs/editor/editor.api';
import editorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker';
import 'monaco-editor/esm/vs/language/typescript/monaco.contribution';
import tsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker?worker';
import Editor, { type OnMount } from '@monaco-editor/react';
import './automation-ide.css';

(self as any).MonacoEnvironment = {
  getWorker(_: string, label: string) {
    if (label === 'typescript' || label === 'javascript') return new tsWorker();
    return new editorWorker();
  },
};

loader.config({ monaco });
import { useEffect, useMemo, useRef, useState } from 'react';
import { getBridgeBasesFromPage, type BridgeBases } from '../services/bridgeBase';
import { deviceLabel, listDevices, type UnifiedDevice } from '../services/deviceRegistry';
import { defaultScriptPath, deleteWorkspacePath, listWorkspaceFiles, readWorkspaceFile, writeWorkspaceFile, type FileEntry } from '../services/fileManager';
import { formatLogTime, type IdeLog, type LogLevel } from '../services/logBus';
import { runBrowserScript } from '../services/scriptRuntime';
import { TLinkautoDeviceSdk } from '../services/tlinkautoSdk';
import { IdeScreenPanel } from './IdeScreenPanel';

const defaultScript = `log("start");
await device.tap(100, 200);
await sleep(500);
log("done");
`;

let logId = 1;

type MonacoEditor = Parameters<OnMount>[0];
type Monaco = Parameters<OnMount>[1];

const automationApiTypes = `
type SmartWaitOptions = {
  timeoutMs?: number;
  intervalMs?: number;
  stableFrames?: number;
  ignoreErrors?: boolean;
  throwOnTimeout?: boolean;
  signal?: AbortSignal;
};
type SmartWaitResult<T> = {
  schema: "smart_wait_result_v1";
  kind: string;
  ok: boolean;
  found: boolean;
  timedOut: boolean;
  cancelled: boolean;
  attempts: number;
  elapsedMs: number;
  stableMatches: number;
  value?: T;
  lastError: string;
};
declare const device: {
  tap(x: number, y: number, holdMs?: number): Promise<void>;
  swipe(x1: number, y1: number, x2: number, y2: number, durationMs?: number): Promise<void>;
  zoom(centerX: number, centerY: number, startRadius: number, endRadius: number, options?: {
    durationMs?: number;
    fingerCount?: 2 | 3;
    steps?: number;
    angleDegrees?: number;
    baseFinger?: number;
  }): Promise<void>;
  getScreenSize(): Promise<{ width: number; height: number } | null>;
  screenshot(path: string, region?: [number, number, number, number]): Promise<string>;
  getRunHistory(): Promise<{ schema: 'run_history_v1'; total_count: number; failed_count: number; runs: Array<{ run_id: string; state: string; duration_ms: number; error: string; failure_evidence: unknown }> }>;
  pickColor(x: number, y: number): Promise<{ red: number; green: number; blue: number; hex: string }>;
  colorEquals(x: number, y: number, hex: string, tolerance?: number): Promise<boolean>;
  frontMostAppId(): Promise<string>;
  waitUntil<T>(predicate: (attempt: number) => T | false | null | undefined | Promise<T | false | null | undefined>, options?: SmartWaitOptions): Promise<SmartWaitResult<T>>;
  waitForApp(bundleId: string, options?: SmartWaitOptions): Promise<SmartWaitResult<string>>;
  waitForColor(x: number, y: number, color: string | [number, number, number] | { red: number; green: number; blue: number }, options?: SmartWaitOptions & { tolerance?: number }): Promise<SmartWaitResult<{ red: number; green: number; blue: number; hex: string }>>;
  findImage(imagePath: string, options?: {
    region?: [number, number, number, number];
    acceptable?: number;
    scaleMin?: number;
    scaleMax?: number;
    scaleStep?: number;
    pixelSkip?: number;
  }): Promise<{ found: boolean; x: number; y: number; width: number; height: number; centerX: number; centerY: number; score: number }>;
  waitForImage(imagePath: string, options?: SmartWaitOptions & {
    region?: [number, number, number, number];
    acceptable?: number;
    scaleMin?: number;
    scaleMax?: number;
    scaleStep?: number;
    pixelSkip?: number;
  }): Promise<SmartWaitResult<{ found: boolean; x: number; y: number; width: number; height: number; centerX: number; centerY: number; score: number }>>;
  waitUntilGone(imagePath: string, options?: SmartWaitOptions & {
    region?: [number, number, number, number];
    acceptable?: number;
  }): Promise<SmartWaitResult<unknown> & { gone: boolean }>;
  tapWhenVisible(imagePath: string, options?: SmartWaitOptions & {
    region?: [number, number, number, number];
    acceptable?: number;
    offsetX?: number;
    offsetY?: number;
    holdMs?: number;
  }): Promise<SmartWaitResult<unknown> & { tapped: boolean; tapX?: number; tapY?: number }>;
  captureImage(region: [number, number, number, number]): Promise<{ id: number; width: number; height: number; region?: [number, number, number, number] }>;
  findImageObject(image: { id: number } | number, options?: {
    region?: [number, number, number, number];
    acceptable?: number;
    scaleMin?: number;
    scaleMax?: number;
    scaleStep?: number;
    pixelSkip?: number;
  }): Promise<{ found: boolean; x: number; y: number; width: number; height: number; centerX: number; centerY: number; score: number }>;
  releaseImage(image: { id: number } | number): Promise<void>;
  ocr(options: {
    region: [number, number, number, number];
    lang?: string;
    psm?: number;
    scaleUp?: number;
    whitelist?: string;
  }): Promise<{ text: string; raw: string[] }>;
  waitForText(text: string, options?: SmartWaitOptions & {
    region?: [number, number, number, number];
    lang?: string;
    psm?: number;
    scaleUp?: number;
    whitelist?: string;
    matchMode?: "contains" | "equals" | "regex";
    caseSensitive?: boolean;
  }): Promise<SmartWaitResult<{ text: string; raw: string[] }>>;
  request(task: number, ...args: Array<string | number>): Promise<{ ok: boolean; parts: string[]; raw: string }>;
};
declare function sleep(ms: number): Promise<void>;
declare function log(message: unknown): void;
declare function assert(condition: unknown, message?: string): void;
declare const signal: AbortSignal;
`;

const completionSnippets = [
  {
    label: 'device.tap',
    detail: 'Tap screen coordinate',
    insertText: 'await device.tap(${1:x}, ${2:y});',
  },
  {
    label: 'device.swipe',
    detail: 'Swipe between coordinates',
    insertText: 'await device.swipe(${1:x1}, ${2:y1}, ${3:x2}, ${4:y2}, ${5:300});',
  },
  {
    label: 'device.zoom',
    detail: 'Two- or three-finger pinch/spread',
    insertText: 'await device.zoom(${1:centerX}, ${2:centerY}, ${3:60}, ${4:160}, { durationMs: ${5:300}, fingerCount: ${6:2}, steps: ${7:20} });',
  },
  {
    label: 'device.getScreenSize',
    detail: 'Read iOS screen size',
    insertText: 'const size = await device.getScreenSize();\nlog(size);',
  },
  {
    label: 'device.screenshot',
    detail: 'Save screenshot or region PNG on device',
    insertText: 'const path = await device.screenshot("${1:/var/mobile/Library/TLinkauto/templates/template.png}", [${2:x}, ${3:y}, ${4:w}, ${5:h}]);\nlog(path);',
  },
  {
    label: 'device.getRunHistory',
    detail: 'Read persistent script runs and failure evidence from task 60',
    insertText: 'const history = await device.getRunHistory();\nlog(history.runs);',
  },
  {
    label: 'device.pickColor',
    detail: 'Pick RGB/HEX color at coordinate',
    insertText: 'const color = await device.pickColor(${1:x}, ${2:y});\nlog(color);',
  },
  {
    label: 'device.colorEquals',
    detail: 'Compare picked color with tolerance',
    insertText: 'const ok = await device.colorEquals(${1:x}, ${2:y}, "${3:#FFFFFF}", ${4:10});',
  },
  {
    label: 'device.waitForApp',
    detail: 'Wait until an app becomes foreground',
    insertText: 'const app = await device.waitForApp("${1:com.example.app}", { timeoutMs: ${2:10000}, signal });\nassert(app.ok, `App wait failed: ${app.lastError}`);',
  },
  {
    label: 'device.waitForColor',
    detail: 'Wait for a stable color match',
    insertText: 'const color = await device.waitForColor(${1:x}, ${2:y}, "${3:#FFFFFF}", { tolerance: ${4:10}, stableFrames: ${5:2}, timeoutMs: ${6:10000}, signal });\nassert(color.ok, "Color not found");',
  },
  {
    label: 'device.findImage',
    detail: 'Find template image in region',
    insertText: 'const found = await device.findImage("${1:/var/mobile/Library/TLinkauto/templates/template.png}", {\n  region: [${2:x}, ${3:y}, ${4:w}, ${5:h}],\n  acceptable: ${6:0.9},\n  scaleMin: ${7:1},\n  scaleMax: ${8:1},\n  pixelSkip: ${9:1}\n});\nlog(found);',
  },
  {
    label: 'device.captureImage',
    detail: 'Capture region as in-memory template image',
    insertText: 'const template = await device.captureImage([${1:x}, ${2:y}, ${3:w}, ${4:h}]);\ntry {\n  const found = await device.findImageObject(template, {\n    region: [${5:0}, ${6:0}, ${7:0}, ${8:0}],\n    acceptable: ${9:0.9},\n    scaleMin: ${10:1},\n    scaleMax: ${11:1},\n    pixelSkip: ${12:1}\n  });\n  log(found);\n} finally {\n  await device.releaseImage(template);\n}',
  },
  {
    label: 'device.waitForImage',
    detail: 'Wait for a stable template match using fresh frames',
    insertText: 'const match = await device.waitForImage("${1:/var/mobile/Library/TLinkauto/templates/button.png}", {\n  region: [${2:x}, ${3:y}, ${4:w}, ${5:h}],\n  acceptable: ${6:0.9},\n  stableFrames: ${7:2},\n  timeoutMs: ${8:10000},\n  signal\n});\nassert(match.ok, `Image wait failed: ${match.lastError}`);',
  },
  {
    label: 'device.tapWhenVisible',
    detail: 'Wait for an image and tap its center',
    insertText: 'const tapped = await device.tapWhenVisible("${1:/var/mobile/Library/TLinkauto/templates/button.png}", { timeoutMs: ${2:10000}, stableFrames: ${3:2}, signal });\nassert(tapped.ok && tapped.tapped, "Target was not tapped");',
  },
  {
    label: 'device.waitUntilGone',
    detail: 'Wait until a template disappears',
    insertText: 'const gone = await device.waitUntilGone("${1:/var/mobile/Library/TLinkauto/templates/loading.png}", { timeoutMs: ${2:15000}, stableFrames: ${3:2}, signal });\nassert(gone.ok && gone.gone, "Loading indicator is still visible");',
  },
  {
    label: 'device.ocr',
    detail: 'Run Tesseract OCR on region',
    insertText: 'const text = await device.ocr({\n  region: [${1:x}, ${2:y}, ${3:w}, ${4:h}],\n  lang: "${5:vie}",\n  psm: ${6:7},\n  scaleUp: ${7:2}\n});\nlog(text);',
  },
  {
    label: 'device.waitForText',
    detail: 'Wait for OCR text with contains, equals or regex matching',
    insertText: 'const text = await device.waitForText("${1:Đăng nhập}", {\n  region: [${2:x}, ${3:y}, ${4:w}, ${5:h}],\n  lang: "${6:vie}",\n  matchMode: "${7:contains}",\n  stableFrames: ${8:2},\n  timeoutMs: ${9:10000},\n  signal\n});\nassert(text.ok, `Text wait failed: ${text.lastError}`);',
  },
  {
    label: 'device.request',
    detail: 'Raw TLinkauto task request',
    insertText: 'const response = await device.request(${1:25}, ${2:1});\nlog(response);',
  },
  {
    label: 'sleep',
    detail: 'Abort-aware delay',
    insertText: 'await sleep(${1:500});',
  },
  {
    label: 'log',
    detail: 'Write to IDE logs',
    insertText: 'log(${1:message});',
  },
  {
    label: 'assert',
    detail: 'Throw if condition is false',
    insertText: 'assert(${1:condition}, ${2:"message"});',
  },
];

export function AutomationIdeApp() {
  const [bases, setBases] = useState<BridgeBases>(() => getBridgeBasesFromPage());
  const [devices, setDevices] = useState<UnifiedDevice[]>([]);
  const [selectedDeviceId, setSelectedDeviceId] = useState('');
  const [script, setScript] = useState(defaultScript);
  const [scriptEntries, setScriptEntries] = useState<FileEntry[]>([]);
  const [selectedFilePath, setSelectedFilePath] = useState('/demo.js');
  const [isDirty, setIsDirty] = useState(false);
  const [screenSize, setScreenSize] = useState<{ width: number; height: number } | null>(null);
  const [tapPoint, setTapPoint] = useState({ x: 120, y: 500 });
  const [swipePoint, setSwipePoint] = useState({ x1: 100, y1: 700, x2: 100, y2: 200, duration: 300 });
  const [colorPoint, setColorPoint] = useState({ x: 120, y: 500, tolerance: 10 });
  const [pickedColor, setPickedColor] = useState<{ red: number; green: number; blue: number; hex: string } | null>(null);
  const [logs, setLogs] = useState<IdeLog[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [status, setStatus] = useState('Ready');
  const runnerAbort = useRef<AbortController | null>(null);
  const logsEndRef = useRef<HTMLDivElement | null>(null);
  const editorRef = useRef<MonacoEditor | null>(null);
  const saveScriptRef = useRef<() => void>(() => {});

  const iosDevices = useMemo(() => devices.filter((d) => d.platform === 'ios' && d.status === 'online'), [devices]);
  const selectedDevice = useMemo(
    () => iosDevices.find((d) => d.id === selectedDeviceId),
    [iosDevices, selectedDeviceId]
  );

  const addLog = (level: LogLevel, source: string, message: unknown) => {
    const text = typeof message === 'string' ? message : JSON.stringify(message, null, 2);
    setLogs((current) => [...current.slice(-400), { id: logId++, time: Date.now(), level, source, message: text }]);
  };

  const refreshDevices = async () => {
    try {
      const nextBases = getBridgeBasesFromPage();
      setBases(nextBases);
      const nextDevices = await listDevices(nextBases.httpBase);
      setDevices(nextDevices);
      const nextIos = nextDevices.filter((d) => d.platform === 'ios' && d.status === 'online');
      setSelectedDeviceId((current) => current || nextIos[0]?.id || '');
      setStatus(`Devices: ${nextIos.length} iOS online`);
    } catch (error) {
      setStatus('Device refresh failed');
      addLog('error', 'ide', error instanceof Error ? error.message : String(error));
    }
  };

  const refreshScripts = async () => {
    try {
      const nextBases = getBridgeBasesFromPage();
      setBases(nextBases);
      const listing = await listWorkspaceFiles(nextBases.httpBase, 'scripts');
      setScriptEntries(listing.entries);
      const nextPath = selectedFilePath || defaultScriptPath(listing.entries);
      if (!selectedFilePath && nextPath) setSelectedFilePath(nextPath);
      setStatus(`Scripts: ${listing.entries.filter((entry) => entry.kind === 'file').length}`);
    } catch (error) {
      addLog('error', 'files', error instanceof Error ? error.message : String(error));
    }
  };

  const openScript = async (path: string) => {
    try {
      const file = await readWorkspaceFile(bases.httpBase, 'scripts', path);
      setSelectedFilePath(file.path);
      setScript(file.content);
      setIsDirty(false);
      setStatus(`Opened ${file.path}`);
    } catch (error) {
      addLog('error', 'files', error instanceof Error ? error.message : String(error));
    }
  };

  const saveScript = async () => {
    try {
      const result = await writeWorkspaceFile(bases.httpBase, 'scripts', selectedFilePath, script);
      setIsDirty(false);
      setStatus(`Saved ${selectedFilePath}`);
      addLog('info', 'files', result.backupPath ? `saved ${selectedFilePath}, backup ${result.backupPath}` : `saved ${selectedFilePath}`);
      await refreshScripts();
    } catch (error) {
      addLog('error', 'files', error instanceof Error ? error.message : String(error));
    }
  };

  saveScriptRef.current = () => {
    saveScript();
  };

  const newScript = async () => {
    if (isDirty && !window.confirm('Current script has unsaved changes. Create a new script anyway?')) return;
    const rawName = window.prompt('New script path under scripts/', 'new-script.js');
    if (!rawName) return;
    const path = normalizeScriptPath(rawName);
    try {
      const content = `log("${path} start");\n`;
      await writeWorkspaceFile(bases.httpBase, 'scripts', path, content);
      await refreshScripts();
      setSelectedFilePath(path);
      setScript(content);
      setIsDirty(false);
      setStatus(`Created ${path}`);
      addLog('info', 'files', `created ${path}`);
    } catch (error) {
      addLog('error', 'files', error instanceof Error ? error.message : String(error));
    }
  };

  const deleteScript = async () => {
    if (!selectedFilePath) return;
    if (!window.confirm(`Delete ${selectedFilePath}?`)) return;
    try {
      await deleteWorkspacePath(bases.httpBase, 'scripts', selectedFilePath);
      addLog('warn', 'files', `deleted ${selectedFilePath}`);
      setSelectedFilePath('/demo.js');
      setScript(defaultScript);
      setIsDirty(false);
      await refreshScripts();
      setStatus('Deleted');
    } catch (error) {
      addLog('error', 'files', error instanceof Error ? error.message : String(error));
    }
  };

  const fetchScreenSize = async () => {
    if (!selectedDevice) {
      addLog('warn', 'tools', 'Select an online iOS device first.');
      return;
    }
    const device = new TLinkautoDeviceSdk(bases.wsBase, selectedDevice.id);
    try {
      const size = await device.getScreenSize();
      if (!size) throw new Error('device did not return screen size');
      setScreenSize(size);
      setStatus(`Screen ${size.width}x${size.height}`);
      addLog('info', 'tools', `screen ${size.width}x${size.height}`);
    } catch (error) {
      addLog('error', 'tools', error instanceof Error ? error.message : String(error));
    } finally {
      device.close();
    }
  };

  const runQuickTap = async () => {
    if (!selectedDevice) {
      addLog('warn', 'tools', 'Select an online iOS device first.');
      return;
    }
    const device = new TLinkautoDeviceSdk(bases.wsBase, selectedDevice.id);
    try {
      await device.tap(tapPoint.x, tapPoint.y);
      addLog('info', 'tools', `tap ${tapPoint.x},${tapPoint.y}`);
    } catch (error) {
      addLog('error', 'tools', error instanceof Error ? error.message : String(error));
    } finally {
      device.close();
    }
  };

  const runQuickSwipe = async () => {
    if (!selectedDevice) {
      addLog('warn', 'tools', 'Select an online iOS device first.');
      return;
    }
    const device = new TLinkautoDeviceSdk(bases.wsBase, selectedDevice.id);
    try {
      await device.swipe(swipePoint.x1, swipePoint.y1, swipePoint.x2, swipePoint.y2, swipePoint.duration);
      addLog('info', 'tools', `swipe ${swipePoint.x1},${swipePoint.y1} -> ${swipePoint.x2},${swipePoint.y2}`);
    } catch (error) {
      addLog('error', 'tools', error instanceof Error ? error.message : String(error));
    } finally {
      device.close();
    }
  };

  const pickColor = async () => {
    if (!selectedDevice) {
      addLog('warn', 'tools', 'Select an online iOS device first.');
      return;
    }
    const device = new TLinkautoDeviceSdk(bases.wsBase, selectedDevice.id);
    try {
      const color = await device.pickColor(colorPoint.x, colorPoint.y);
      setPickedColor(color);
      setStatus(`Color ${color.hex}`);
      addLog('info', 'tools', `color ${colorPoint.x},${colorPoint.y} = ${color.hex} rgb(${color.red},${color.green},${color.blue})`);
    } catch (error) {
      addLog('error', 'tools', error instanceof Error ? error.message : String(error));
    } finally {
      device.close();
    }
  };

  const runScript = async () => {
    if (!selectedDevice) {
      addLog('warn', 'runner', 'Select an online iOS device first.');
      return;
    }

    const abort = new AbortController();
    const device = new TLinkautoDeviceSdk(bases.wsBase, selectedDevice.id);
    runnerAbort.current = abort;
    setIsRunning(true);
    setStatus(`Running on ${deviceLabel(selectedDevice)}`);
    addLog('info', 'runner', `run ${deviceLabel(selectedDevice)}`);

    try {
      await device.waitOpen(1500);
      await runBrowserScript(script, {
        device,
        signal: abort.signal,
        log: (message) => addLog('info', 'script', message),
      });
      addLog('info', 'runner', 'script completed');
      setStatus('Completed');
    } catch (error) {
      if (abort.signal.aborted) {
        addLog('warn', 'runner', 'script stopped');
        setStatus('Stopped');
      } else {
        addLog('error', 'runner', error instanceof Error ? error.stack || error.message : String(error));
        setStatus('Failed');
      }
    } finally {
      device.close();
      runnerAbort.current = null;
      setIsRunning(false);
    }
  };

  const stopScript = () => {
    runnerAbort.current?.abort();
  };

  const insertSnippet = (snippet: string) => {
    const editor = editorRef.current;
    if (!editor) {
      setScript((current) => `${current.trimEnd()}\n${snippet}\n`);
      setIsDirty(true);
      return;
    }

    const selection = editor.getSelection();
    if (!selection) return;
    editor.executeEdits('automation-ide', [{ range: selection, text: snippet, forceMoveMarkers: true }]);
    editor.focus();
    setScript(editor.getValue());
    setIsDirty(true);
  };

  const handleEditorMount: OnMount = (editor, monaco) => {
    editorRef.current = editor;
    configureMonaco(monaco);
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => {
      saveScriptRef.current();
    });
  };

  useEffect(() => {
    refreshDevices();
    refreshScripts();
    const timer = window.setInterval(refreshDevices, 5000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    logsEndRef.current?.scrollIntoView({ block: 'end' });
  }, [logs]);

  return (
    <div className="automation-ide-shell">
      <header className="automation-ide-topbar">
        <div>
          <div className="automation-ide-title">Automation IDE</div>
        </div>
        <div className="automation-ide-actions">
          <select value={selectedDeviceId} onChange={(e) => setSelectedDeviceId(e.target.value)}>
            <option value="">Select iOS device</option>
            {iosDevices.map((device) => (
              <option key={device.id} value={device.id}>{deviceLabel(device)}</option>
            ))}
          </select>
          <button type="button" onClick={refreshDevices}>Refresh</button>
          <button type="button" disabled={!isDirty} onClick={saveScript}>Save</button>
          <button type="button" className="primary" disabled={isRunning} onClick={runScript}>Run</button>
          <button type="button" className="danger" disabled={!isRunning} onClick={stopScript}>Stop</button>
        </div>
      </header>

      <main className="automation-ide-grid">
        <aside className="automation-ide-panel file-panel">
          <div className="panel-title">Workspace</div>
          <div className="file-panel-actions">
            <button type="button" onClick={newScript}>New</button>
            <button type="button" onClick={refreshScripts}>Refresh</button>
            <button type="button" className="danger" onClick={deleteScript}>Delete</button>
          </div>
          {scriptEntries.length === 0 ? <div className="file-row muted">scripts/ is empty</div> : null}
          {scriptEntries.map((entry) => (
            <button
              type="button"
              key={entry.path}
              className={`file-row ${entry.path === selectedFilePath ? 'active' : ''} ${entry.kind === 'directory' ? 'muted' : ''}`}
              disabled={entry.kind === 'directory'}
              onClick={() => openScript(entry.path)}
            >
              {entry.kind === 'directory' ? `${entry.name}/` : entry.name}
            </button>
          ))}
          <div className="file-row muted">templates/</div>
          <div className="panel-note">Scripts are stored in bridge workspace. Saves create .bak and history copies.</div>
        </aside>

        <section className="automation-ide-panel editor-panel">
          <div className="editor-toolbar">
            <span>{selectedFilePath}{isDirty ? ' *' : ''}</span>
            <span className="status-pill">{status}</span>
          </div>
          <div className="script-editor-host">
            <Editor
              height="100%"
              defaultLanguage="javascript"
              language="javascript"
              path="scripts/demo.js"
              value={script}
              theme="automation-light"
              onChange={(value) => {
                setScript(value || '');
                setIsDirty(true);
              }}
              onMount={handleEditorMount}
              options={{
                automaticLayout: true,
                fontFamily: 'JetBrains Mono, Consolas, monospace',
                fontSize: 13,
                fontLigatures: true,
                minimap: { enabled: false },
                scrollBeyondLastLine: false,
                tabSize: 2,
                wordWrap: 'on',
                quickSuggestions: true,
                suggestSelection: 'first',
              }}
            />
          </div>
        </section>

        <aside className="automation-ide-panel tools-panel">
          <IdeScreenPanel
            device={selectedDevice}
            httpBase={bases.httpBase}
            wsBase={bases.wsBase}
            insertSnippet={insertSnippet}
            addLog={addLog}
          />
        </aside>
      </main>

      <section className="automation-ide-logs">
        <div className="logs-header">
          <span>Logs</span>
          <button type="button" onClick={() => setLogs([])}>Clear</button>
        </div>
        <div className="logs-body">
          {logs.length === 0 ? <div className="log-empty">No logs yet.</div> : null}
          {logs.map((log) => (
            <div className={`log-line ${log.level}`} key={log.id}>
              <span className="log-time">{formatLogTime(log.time)}</span>
              <span className="log-source">{log.source}</span>
              <span className="log-message">{log.message}</span>
            </div>
          ))}
          <div ref={logsEndRef} />
        </div>
      </section>
    </div>
  );
}

function configureMonaco(monaco: Monaco) {
  monaco.editor.defineTheme('automation-light', {
    base: 'vs',
    inherit: true,
    rules: [],
    colors: {
      'editor.background': '#fbfdff',
      'editorLineNumber.foreground': '#94a3b8',
      'editor.lineHighlightBackground': '#eff6ff80',
    },
  });

  const typescript = monaco.languages.typescript;
  if (typescript) {
    typescript.javascriptDefaults.setCompilerOptions({
      allowNonTsExtensions: true,
      checkJs: true,
      target: typescript.ScriptTarget.ES2020,
    });
    typescript.javascriptDefaults.setDiagnosticsOptions({
      noSemanticValidation: false,
      noSyntaxValidation: false,
    });
    apiTypesDisposable?.dispose();
    apiTypesDisposable = typescript.javascriptDefaults.addExtraLib(automationApiTypes, 'automation-api.d.ts');
  }

  completionProviderDisposable?.dispose();
  completionProviderDisposable = monaco.languages.registerCompletionItemProvider('javascript', {
    triggerCharacters: ['.', 'a', 'd', 'l'],
    provideCompletionItems: (model, position) => {
      const word = model.getWordUntilPosition(position);
      const range = new monaco.Range(position.lineNumber, word.startColumn, position.lineNumber, word.endColumn);
      return {
        suggestions: completionSnippets.map((snippet) => ({
          label: snippet.label,
          kind: monaco.languages.CompletionItemKind.Snippet,
          detail: snippet.detail,
          insertText: snippet.insertText,
          insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
          range,
        })),
      };
    },
  });
}

let apiTypesDisposable: { dispose: () => void } | undefined;
let completionProviderDisposable: { dispose: () => void } | undefined;

function normalizeScriptPath(path: string) {
  const normalized = path.trim().replace(/\\/g, '/').replace(/^\/+/, '');
  const withExt = normalized.endsWith('.js') ? normalized : `${normalized}.js`;
  return `/${withExt}`;
}

function numberValue(value: string) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}
