import { createStore } from './createStore';

type ModalState = {
  androidModalSerial: string | null;
  iosModalSerial: string | null;
};

export const modalStore = createStore<ModalState>({
  androidModalSerial: null,
  iosModalSerial: null,
});

export const modalActions = {
  openAndroidModal: (serial: string) => modalStore.setState({ androidModalSerial: serial }),
  closeAndroidModal: () => modalStore.setState({ androidModalSerial: null }),
  openIosModal: (serial: string) => modalStore.setState({ iosModalSerial: serial }),
  closeIosModal: () => modalStore.setState({ iosModalSerial: null }),
};
