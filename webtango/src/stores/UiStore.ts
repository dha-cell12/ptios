import { createStore } from './createStore';

export type AppTab = 'devices' | 'screen_view' | 'automation_ide';
export type ScreenViewMode = 'grid' | 'focus';
export type ScreenViewPlatform = 'android' | 'ios';
export type DeviceFilter = 'all' | 'online' | 'offline' | 'usb' | 'wifi';

export type UiState = {
  activeTab: AppTab;
  screenViewMode: ScreenViewMode;
  screenViewPlatform: ScreenViewPlatform;
  screenViewZoom: number;
  deviceFilter: DeviceFilter;
  searchQuery: string;
  shellOpen: boolean;
  pullFileOpen: boolean;
};

export const uiStore = createStore<UiState>({
  activeTab: 'devices',
  screenViewMode: 'grid',
  screenViewPlatform: 'android',
  screenViewZoom: 0.8,
  deviceFilter: 'all',
  searchQuery: '',
  shellOpen: false,
  pullFileOpen: false,
});

export function setActiveTab(tab: AppTab) { uiStore.setState({ activeTab: tab }); }
export function setScreenViewMode(mode: ScreenViewMode) { uiStore.setState({ screenViewMode: mode }); }
export function setScreenViewPlatform(platform: ScreenViewPlatform) { uiStore.setState({ screenViewPlatform: platform }); }
export function setScreenViewZoom(zoom: number) { uiStore.setState({ screenViewZoom: zoom }); }
export function setDeviceFilter(filter: DeviceFilter) { uiStore.setState({ deviceFilter: filter }); }
export function setSearchQuery(query: string) { uiStore.setState({ searchQuery: query }); }
export function setShellOpen(open: boolean) { uiStore.setState({ shellOpen: open }); }
export function setPullFileOpen(open: boolean) { uiStore.setState({ pullFileOpen: open }); }
