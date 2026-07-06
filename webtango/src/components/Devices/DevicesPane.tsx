import { useStore } from '../../stores/useStore';
import { adbDeviceStore } from '../../stores/AdbDeviceStore';
import { iosDeviceStore } from '../../stores/IosDeviceStore';
import { uiStore } from '../../stores/UiStore';
import { modalActions } from '../../stores/ModalStore';
import { FilterPills } from './FilterPills';
import { SearchBox } from './SearchBox';
import { AndroidDeviceTable } from './AndroidDeviceTable';
import { IosDeviceTable } from './IosDeviceTable';
import { DetailPane } from './DetailPane/DetailPane';
import { AdbDeviceController } from '../../controllers/AdbDeviceController';
import { IosDeviceController } from '../../controllers/IosDeviceController';
import type { UnifiedDevice } from '../../services/deviceRegistry';

export function DevicesPane() {
  const activeTab = useStore(uiStore, (s) => s.activeTab);
  const androidCount = useStore(adbDeviceStore, (s) => s.order.length);
  const iosCount = useStore(iosDeviceStore, (s) => s.devices.length);

  if (activeTab !== 'devices') return null;

  const openModal = (serial: string) => modalActions.openAndroidModal(serial);
  const powerOff = (serial: string) => AdbDeviceController.disconnectDevice(serial);
  const openIos = (device: UnifiedDevice) => modalActions.openIosModal(device.id);
  const refresh = () => AdbDeviceController.refreshDevices();

  return (
    <>
      <section className="device-list-pane">
        <div className="list-pane-header">
          <FilterPills />
          <div className="list-actions">
            <SearchBox />
            <button
              type="button"
              className="action-btn header-refresh-btn"
              title="Refresh Connected Devices"
              onClick={refresh}
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8" />
                <path d="M3 3v5h5" />
                <path d="M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16" />
                <path d="M16 16h5v5" />
              </svg>
            </button>
            <div className="list-meta">
              <span className="list-count" id="device-count">Android ({androidCount})</span>
              <span className="auto-update">Auto-Sync ON</span>
            </div>
          </div>
        </div>

        <div className="table-header-row">
          <div className="col-checkbox"><input type="checkbox" disabled className="table-checkbox" /></div>
          <div className="col-no">No</div>
          <div className="col-serial">Serial Number</div>
          <div className="col-model">Device Model &amp; Version</div>
          <div className="col-platform">Platform</div>
          <div className="col-status">Status</div>
        </div>

        <AndroidDeviceTable onOpenModal={openModal} onPowerOff={powerOff} />

        <div className="list-pane-header ios-divider-header">
          <div className="list-meta">
            <span className="list-count" id="ios-device-count">iOS ({iosCount})</span>
            <span className="ios-badge">TCP 6000</span>
          </div>
        </div>

        <div className="table-header-row">
          <div className="col-checkbox"><input type="checkbox" disabled className="table-checkbox" /></div>
          <div className="col-no">No</div>
          <div className="col-serial">Device ID</div>
          <div className="col-model">Model &amp; Meta</div>
          <div className="col-platform">Platform</div>
          <div className="col-status">Status</div>
        </div>

        <IosDeviceTable onOpenStream={openIos} />
      </section>
      
      <DetailPane />
    </>
  );
}
