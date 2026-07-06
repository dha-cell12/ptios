import React, { Suspense } from 'react';
import { useStore } from '../stores/useStore';
import { uiStore } from '../stores/UiStore';
import { DevicesPane } from './Devices/DevicesPane';
import { ScreenViewGrid } from './screen-view/ScreenViewGrid';

const AutomationIdeApp = React.lazy(() => import('../ide/AutomationIdeApp').then(module => ({ default: module.AutomationIdeApp })));

export function MainContent() {
  const activeTab = useStore(uiStore, (s) => s.activeTab);

  return (
    <main id="main-content" className="content-area">
      {activeTab === 'devices' && <DevicesPane />}
      {activeTab === 'screen_view' && <ScreenViewGrid />}
      {activeTab === 'automation_ide' && (
        <Suspense fallback={<div style={{ padding: 24 }}>Loading Automation IDE...</div>}>
          <AutomationIdeApp />
        </Suspense>
      )}
      
      {activeTab !== 'devices' && activeTab !== 'screen_view' && activeTab !== 'automation_ide' && (
        <div style={{ padding: 24, color: 'var(--muted-foreground)' }}>
          React shell active. Current tab: <strong>{activeTab}</strong>.
        </div>
      )}
    </main>
  );
}
