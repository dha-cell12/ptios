import Editor, { type OnMount } from '@monaco-editor/react';
import { useEffect, useMemo, useRef, useState } from 'react';
import { getBridgeBasesFromPage, type BridgeBases } from '../services/bridgeBase';
import { deviceLabel, listDevices, type UnifiedDevice } from '../services/deviceRegistry';
import { defaultScriptPath, listWorkspaceFiles, readWorkspaceFile, writeWorkspaceFile, type FileEntry } from '../services/fileManager';
import { formatLogTime, type IdeLog, type LogLevel } from '../services/logBus';
import { runBrowserScript } from '../services/scriptRuntime';
import { ZxTouchDeviceSdk } from '../services/zxtouchSdk';

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
  const [logs, setLogs] = useState<IdeLog[]>([]);
  const [isRunning, setIsRunning] = useState(false);
  const [status, setStatus] = useState('Ready');
  const runnerAbort = useRef<AbortController | null>(null);
  const logsEndRef = useRef<HTMLDivElement | null>(null);
  const editorRef = useRef<MonacoEditor | null>(null);

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
            <button type="button" onClick={refreshScripts}>Refresh</button>
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
          <div className="panel-title">Insert</div>
          <button type="button" onClick={() => insertSnippet('await device.tap(120, 500);')}>tap(x, y)</button>
          <button type="button" onClick={() => insertSnippet('await device.swipe(100, 700, 100, 200, 300);')}>swipe(...)</button>
          <button type="button" onClick={() => insertSnippet('const size = await device.getScreenSize();\nlog(size);')}>screen size</button>
          <button type="button" onClick={() => insertSnippet('const response = await device.request(25, 1);\nlog(response);')}>raw task</button>
          <div className="panel-note">Next slices: screen click coordinates, native color picker, template crop, OCR region.</div>
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
