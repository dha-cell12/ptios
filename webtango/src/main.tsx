import React from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './components/App';

import './style.css';
import './screen-view.css';

const rootEl = document.getElementById('root');
if (rootEl) {
  createRoot(rootEl).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>
  );
} else {
  console.warn('[main.tsx] #root not found, React shell not mounted');
}
