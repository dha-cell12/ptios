import { createStore } from './createStore';
import type { ScrcpyMirrorSession } from '../services/adb/ScrcpyMirror';

export type ScrcpyMirrorStoreState = {
  sessions: Record<string, ScrcpyMirrorSession>;
};

export const scrcpyMirrorStore = createStore<ScrcpyMirrorStoreState>({
  sessions: {},
});

export function registerMirrorSession(session: ScrcpyMirrorSession) {
  const { sessions } = scrcpyMirrorStore.getState();
  scrcpyMirrorStore.setState({
    sessions: { ...sessions, [session.serial]: session },
  });
}

export function unregisterMirrorSession(serial: string) {
  const { sessions } = scrcpyMirrorStore.getState();
  if (!(serial in sessions)) return;
  const next = { ...sessions };
  delete next[serial];
  scrcpyMirrorStore.setState({ sessions: next });
}

export function getMirrorSession(serial: string): ScrcpyMirrorSession | undefined {
  return scrcpyMirrorStore.getState().sessions[serial];
}
