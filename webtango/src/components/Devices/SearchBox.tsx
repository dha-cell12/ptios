import { useStore } from '../../stores/useStore';
import { uiStore, setSearchQuery } from '../../stores/UiStore';

export function SearchBox() {
  const query = useStore(uiStore, (s) => s.searchQuery);
  return (
    <div className="search-container">
      <span className="search-icon">
        <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="11" cy="11" r="8" />
          <path d="m21 21-4.3-4.3" />
        </svg>
      </span>
      <input
        type="text"
        placeholder="Search devices..."
        className="search-input"
        value={query}
        onChange={(e) => setSearchQuery(e.target.value)}
      />
    </div>
  );
}
