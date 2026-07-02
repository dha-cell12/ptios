import { useEffect } from 'react';
import { Sidebar } from './Sidebar';
import { Header } from './Header';
import { MainContent } from './MainContent';
import { uiStore } from '../stores/UiStore';

// AppShell mirrors the legacy .app-container layout but is opt-in: it only
// renders when the React root is mounted, so the existing vanilla DOM can keep
// running in parallel during the slice-by-slice migration.
export function AppShell() {
  useEffect(() => {
    // Keep the legacy `.nav-item.active` selector in sync with the React store
    // so DOM scripts that still inspect it (visibility, screen-view rerender)
    // continue to work until those code paths move over.
    const unsubscribe = uiStore.subscribe(() => {
      const tab = uiStore.getState().activeTab;
      document.querySelectorAll('.nav-item').forEach((el) => {
        el.classList.toggle('active', (el as HTMLElement).dataset.tab === tab);
      });
      window.dispatchEvent(new CustomEvent('automation-ide-visibility', {
        detail: { visible: tab === 'automation_ide' },
      }));
    });
    return unsubscribe;
  }, []);

  return (
    <div className="app-container">
      <Sidebar />
      <div className="main-wrapper">
        <Header />
        <MainContent />
      </div>
    </div>
  );
}
