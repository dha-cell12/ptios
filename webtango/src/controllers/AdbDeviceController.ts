type DisconnectListener = (serial: string) => void;
type RefreshListener = () => void;

class AdbDeviceControllerImpl {
  private disconnectListeners = new Set<DisconnectListener>();
  private refreshListeners = new Set<RefreshListener>();

  onDisconnect(listener: DisconnectListener) {
    this.disconnectListeners.add(listener);
    return () => this.disconnectListeners.delete(listener);
  }

  onRefresh(listener: RefreshListener) {
    this.refreshListeners.add(listener);
    return () => this.refreshListeners.delete(listener);
  }

  disconnectDevice(serial: string) {
    this.disconnectListeners.forEach(l => l(serial));
  }

  refreshDevices() {
    this.refreshListeners.forEach(l => l());
  }
}

export const AdbDeviceController = new AdbDeviceControllerImpl();
