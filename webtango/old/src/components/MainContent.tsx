import { useStore } from '../stores/useStore';
import { uiStore } from '../stores/UiStore';
import { DevicesPane } from './Devices/DevicesPane';

// Slice C: Devices tab is now React. Other tabs still rendered by legacy DOM
// until later slices replace them.
export function MainContent() {
  const activeTab = useStore(uiStore, (s) => s.activeTab);

  return (
    <div id="main-content" className="content-area">
      <DevicesPane />
      {activeTab !== 'devices' && (
        <div style={{ padding: 24, color: 'var(--muted-foreground)' }}>
          React shell active. Current tab: <strong>{activeTab}</strong>. Legacy DOM panes still render underneath until the next migration slice.
        </div>
      )}
    </div>
  );
}
