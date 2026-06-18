import Editor, { type OnMount } from '@monaco-editor/react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { getBridgeBasesFromPage, type BridgeBases } from '../services/bridgeBase';
import { deviceLabel, listDevices, type UnifiedDevice } from '../services/deviceRegistry';
import { defaultScriptPath, deleteWorkspacePath, listWorkspaceFiles, readWorkspaceFile, writeWorkspaceFile, type FileEntry } from '../services/fileManager';
import { formatLogTime, type IdeLog, type LogLevel } from '../services/logBus';
import { runBrowserScript } from '../services/scriptRuntime';
import { ZxTouchDeviceSdk } from '../services/zxtouchSdk';
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
declare const device: {
  tap(x: number, y: number, holdMs?: number): Promise<void>;
  swipe(x1: number, y1: number, x2: number, y2: number, durationMs?: number): Promise<void>;
  getScreenSize(): Promise<{ width: number; height: number } | null>;
  screenshot(path: string, region?: [number, number, number, number]): Promise<string>;
  pickColor(x: number, y: number): Promise<{ red: number; green: number; blue: number; hex: string }>;
  colorEquals(x: number, y: number, hex: string, tolerance?: number): Promise<boolean>;
  findImage(imagePath: string, options?: {
    region?: [number, number, number, number];
    acceptable?: number;
    scaleMin?: number;
    scaleMax?: number;
    scaleStep?: number;
    pixelSkip?: number;
  }): Promise<{ x: number; y: number; width: number; height: number; centerX: number; centerY: number; score: number }>;
  captureImage(region: [number, number, number, number]): Promise<{ id: number; width: number; height: number; region?: [number, number, number, number] }>;
  findImageObject(image: { id: number } | number, options?: {
    region?: [number, number, number, number];
    acceptable?: number;
    scaleMin?: number;
    scaleMax?: number;
    scaleStep?: number;
    pixelSkip?: number;
  }): Promise<{ x: number; y: number; width: number; height: number; centerX: number; centerY: number; score: number }>;
  releaseImage(image: { id: number } | number): Promise<void>;
  ocr(options: {
    region: [number, number, number, number];
    lang?: string;
    psm?: number;
    scaleUp?: number;
    whitelist?: string;
  }): Promise<{ text: string; raw: string[] }>;
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
    label: 'device.getScreenSize',
    detail: 'Read iOS screen size',
    insertText: 'const size = await device.getScreenSize();\nlog(size);',
  },
  {
    label: 'device.screenshot',
    detail: 'Save screenshot or region PNG on device',
    insertText: 'const path = await device.screenshot("${1:/var/mobile/Library/ZXTouch/templates/template.png}", [${2:x}, ${3:y}, ${4:w}, ${5:h}]);\nlog(path);',
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
    label: 'device.findImage',
    detail: 'Find template image in region',
    insertText: 'const found = await device.findImage("${1:/var/mobile/Library/ZXTouch/templates/template.png}", {\n  region: [${2:x}, ${3:y}, ${4:w}, ${5:h}],\n  acceptable: ${6:0.8},\n  pixelSkip: ${7:1}\n});\nlog(found);',
  },
  {
    label: 'device.captureImage',
    detail: 'Capture region as in-memory template image',
    insertText: 'const template = await device.captureImage([${1:x}, ${2:y}, ${3:w}, ${4:h}]);\ntry {\n  const found = await device.findImageObject(template, {\n    region: [${5:0}, ${6:0}, ${7:0}, ${8:0}],\n    acceptable: ${9:0.8},\n    pixelSkip: ${10:1}\n  });\n  log(found);\n} finally {\n  await device.releaseImage(template);\n}',
  },
  {
    label: 'device.ocr',
    detail: 'Run Tesseract OCR on region',
    insertText: 'const text = await device.ocr({\n  region: [${1:x}, ${2:y}, ${3:w}, ${4:h}],\n  lang: "${5:vie}",\n  psm: ${6:7},\n  scaleUp: ${7:2}\n});\nlog(text);',
  },
  {
    label: 'device.request',
    detail: 'Raw zxtouch task request',
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
    const device = new ZxTouchDeviceSdk(bases.wsBase, selectedDevice.id);
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
    const device = new ZxTouchDeviceSdk(bases.wsBase, selectedDevice.id);
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
    const device = new ZxTouchDeviceSdk(bases.wsBase, selectedDevice.id);
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
    const device = new ZxTouchDeviceSdk(bases.wsBase, selectedDevice.id);
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
    const device = new ZxTouchDeviceSdk(bases.wsBase, selectedDevice.id);
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
          <div className="automation-ide-subtitle">Browser runner via bridge-rs-new and zxtouch</div>
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
          <div className="panel-title">Device Tools</div>

          <IdeScreenPanel
            device={selectedDevice}
            httpBase={bases.httpBase}
            wsBase={bases.wsBase}
            insertSnippet={insertSnippet}
            addLog={addLog}
          />

          <div className="tool-card">
            <div className="tool-card-title">Screen</div>
            <button type="button" onClick={fetchScreenSize}>Get screen size</button>
            <button type="button" onClick={() => insertSnippet('const size = await device.getScreenSize();\nlog(size);')}>Insert size code</button>
            <div className="tool-readout">{screenSize ? `${screenSize.width} x ${screenSize.height}` : 'Unknown'}</div>
          </div>

          <div className="tool-card">
            <div className="tool-card-title">Tap</div>
            <div className="tool-grid two">
              <label>X<input type="number" value={tapPoint.x} onChange={(e) => setTapPoint((p) => ({ ...p, x: numberValue(e.target.value) }))} /></label>
              <label>Y<input type="number" value={tapPoint.y} onChange={(e) => setTapPoint((p) => ({ ...p, y: numberValue(e.target.value) }))} /></label>
            </div>
            <div className="tool-actions-row">
              <button type="button" onClick={runQuickTap}>Run tap</button>
              <button type="button" onClick={() => insertSnippet(`await device.tap(${tapPoint.x}, ${tapPoint.y});`)}>Insert</button>
            </div>
          </div>

          <div className="tool-card">
            <div className="tool-card-title">Swipe</div>
            <div className="tool-grid two">
              <label>X1<input type="number" value={swipePoint.x1} onChange={(e) => setSwipePoint((p) => ({ ...p, x1: numberValue(e.target.value) }))} /></label>
              <label>Y1<input type="number" value={swipePoint.y1} onChange={(e) => setSwipePoint((p) => ({ ...p, y1: numberValue(e.target.value) }))} /></label>
              <label>X2<input type="number" value={swipePoint.x2} onChange={(e) => setSwipePoint((p) => ({ ...p, x2: numberValue(e.target.value) }))} /></label>
              <label>Y2<input type="number" value={swipePoint.y2} onChange={(e) => setSwipePoint((p) => ({ ...p, y2: numberValue(e.target.value) }))} /></label>
              <label>MS<input type="number" value={swipePoint.duration} onChange={(e) => setSwipePoint((p) => ({ ...p, duration: numberValue(e.target.value) }))} /></label>
            </div>
            <div className="tool-actions-row">
              <button type="button" onClick={runQuickSwipe}>Run swipe</button>
              <button type="button" onClick={() => insertSnippet(`await device.swipe(${swipePoint.x1}, ${swipePoint.y1}, ${swipePoint.x2}, ${swipePoint.y2}, ${swipePoint.duration});`)}>Insert</button>
            </div>
          </div>

          <div className="tool-card">
            <div className="tool-card-title">Color</div>
            <div className="tool-grid two">
              <label>X<input type="number" value={colorPoint.x} onChange={(e) => setColorPoint((p) => ({ ...p, x: numberValue(e.target.value) }))} /></label>
              <label>Y<input type="number" value={colorPoint.y} onChange={(e) => setColorPoint((p) => ({ ...p, y: numberValue(e.target.value) }))} /></label>
              <label>Tol<input type="number" value={colorPoint.tolerance} onChange={(e) => setColorPoint((p) => ({ ...p, tolerance: numberValue(e.target.value) }))} /></label>
            </div>
            <div className="color-readout-row">
              <div className="color-swatch" style={{ background: pickedColor?.hex || 'transparent' }} />
              <div className="tool-readout">
                {pickedColor ? `${pickedColor.hex} rgb(${pickedColor.red}, ${pickedColor.green}, ${pickedColor.blue})` : 'No color picked'}
              </div>
            </div>
            <div className="tool-actions-row">
              <button type="button" onClick={pickColor}>Pick</button>
              <button type="button" onClick={() => insertSnippet(`const color = await device.pickColor(${colorPoint.x}, ${colorPoint.y});\nlog(color);`)}>Insert pick</button>
            </div>
            <button
              type="button"
              disabled={!pickedColor}
              onClick={() => pickedColor && insertSnippet(`const ok = await device.colorEquals(${colorPoint.x}, ${colorPoint.y}, "${pickedColor.hex}", ${colorPoint.tolerance});`)}
            >
              Insert colorEquals
            </button>
          </div>

          <div className="tool-card">
            <div className="tool-card-title">Raw</div>
            <button type="button" onClick={() => insertSnippet('const response = await device.request(25, 1);\nlog(response);')}>Insert raw task</button>
          </div>

          <div className="panel-note">Next slices: native color picker, template crop, OCR region.</div>
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
