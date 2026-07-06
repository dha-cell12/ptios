import { useStore } from '../stores/useStore';
import { uiStore, setActiveTab, type AppTab } from '../stores/UiStore';

type NavItem = { tab: AppTab; label: string; title: string; icon: React.ReactNode };

const NAV: NavItem[] = [
  {
    tab: 'devices',
    label: 'Devices',
    title: 'Devices Dashboard',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <rect width="7" height="9" x="3" y="3" rx="1" />
        <rect width="7" height="5" x="14" y="3" rx="1" />
        <rect width="7" height="9" x="14" y="12" rx="1" />
        <rect width="7" height="5" x="3" y="16" rx="1" />
      </svg>
    ),
  },
  {
    tab: 'screen_view',
    label: 'Screen View',
    title: 'Screen Viewer Grid',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <rect width="20" height="14" x="2" y="3" rx="2" />
        <line x1="8" x2="16" y1="21" y2="21" />
        <line x1="12" x2="12" y1="17" y2="21" />
      </svg>
    ),
  },
  {
    tab: 'automation_ide',
    label: 'IDE',
    title: 'Automation IDE',
    icon: (
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="m18 16 4-4-4-4" />
        <path d="m6 8-4 4 4 4" />
        <path d="m14.5 4-5 16" />
      </svg>
    ),
  },
];

export function Sidebar() {
  const activeTab = useStore(uiStore, (s) => s.activeTab);

  return (
    <aside className="sidebar">
      <div className="sidebar-header">
        <div className="sidebar-logo">T</div>
      </div>
      <nav className="sidebar-nav">
        {NAV.map((item) => (
          <div
            key={item.tab}
            className={`nav-item ${activeTab === item.tab ? 'active' : ''}`}
            data-tab={item.tab}
            title={item.title}
            onClick={() => setActiveTab(item.tab)}
          >
            <span className="nav-icon">{item.icon}</span>
            <span className="nav-label">{item.label}</span>
          </div>
        ))}
      </nav>
      <div className="sidebar-bottom">
        <div className="sidebar-version">1.0.4</div>
      </div>
    </aside>
  );
}
