import { AndroidKeyCode, AndroidKeyEventAction } from '@yume-chan/scrcpy';
import { getMirrorSession } from '../../../stores/ScrcpyMirrorStore';

type Props = {
  serial: string;
};

import { ScrcpyBatchController } from '../../../ScrcpyBatchController';

async function pressKey(serial: string, keyCode: number) {
  const session = getMirrorSession(serial);
  const controller = session?.controller;
  if (!controller) return;
  try {
    await ScrcpyBatchController.injectKey(controller, keyCode);
  } catch (e) {
    console.warn('[control-bar] keyevent failed', e);
  }
}

export function ControlBar({ serial }: Props) {
  const disabled = !getMirrorSession(serial);

  return (
    <div className="control-bar-vertical">
      <button
        className="ctrl-btn"
        title="Back"
        disabled={disabled}
        onClick={() => pressKey(serial, 4)} // Android KeyCode 4 = Back
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-arrow-left"><line x1="19" x2="5" y1="12" y2="12"/><polyline points="12 19 5 12 12 5"/></svg>
      </button>
      <button
        className="ctrl-btn"
        title="Home"
        disabled={disabled}
        onClick={() => pressKey(serial, 3)} // Android KeyCode 3 = Home
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-home"><path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg>
      </button>
      <button
        className="ctrl-btn"
        title="Wake Screen"
        disabled={disabled}
        onClick={() => pressKey(serial, 26)} // Android KeyCode 26 = Power
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-sun"><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/></svg>
      </button>
    </div>
  );
}
