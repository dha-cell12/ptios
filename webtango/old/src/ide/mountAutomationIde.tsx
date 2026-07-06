import { loader } from '@monaco-editor/react';
import * as monaco from 'monaco-editor/esm/vs/editor/editor.api';
import editorWorker from 'monaco-editor/esm/vs/editor/editor.worker?worker';
import 'monaco-editor/esm/vs/language/typescript/monaco.contribution';
import tsWorker from 'monaco-editor/esm/vs/language/typescript/ts.worker?worker';
import React from 'react';
import { createRoot } from 'react-dom/client';
import { AutomationIdeApp } from './AutomationIdeApp';
import './automation-ide.css';

(self as any).MonacoEnvironment = {
  getWorker(_: string, label: string) {
    if (label === 'typescript' || label === 'javascript') return new tsWorker();
    return new editorWorker();
  },
};

loader.config({ monaco });

export function mountAutomationIde(element: HTMLElement) {
  createRoot(element).render(
    <React.StrictMode>
      <AutomationIdeApp />
    </React.StrictMode>
  );
}
