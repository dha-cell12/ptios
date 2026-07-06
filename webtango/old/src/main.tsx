import './style.css';
import './screen-view.css';
import { createRoot } from 'react-dom/client';
import { App } from './components/App';
// Keep legacy vanilla TS running in parallel during the slice migration.
// Each Phase 3 slice replaces a piece of legacy DOM with a React component,
// then the corresponding code path in ./main is removed.
import './main';

const rootEl = document.getElementById('root');
if (rootEl) {
  // StrictMode stays off until Phase 4 — see migration plan, services need
  // double-invoke audit before we re-enable it in dev.
  createRoot(rootEl).render(<App />);
} else {
  console.warn('[main.tsx] #root not found, React shell not mounted');
}
