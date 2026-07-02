import { AndroidKeyCode, AndroidKeyEventAction } from '@yume-chan/scrcpy';
import { getMirrorSession } from '../../../stores/ScrcpyMirrorStore';

type Props = {
  serial: string;
};

async function pressKey(serial: string, keyCode: number) {
  const session = getMirrorSession(serial);
  const controller = session?.controller;
  if (!controller) return;
  try {
    await controller.injectKeyCode({
      action: AndroidKeyEventAction.Down,
      keyCode,
      repeat: 0,
      metaState: 0,
    });
    await controller.injectKeyCode({
      action: AndroidKeyEventAction.Up,
      keyCode,
      repeat: 0,
      metaState: 0,
    });
  } catch (e) {
    console.warn('[control-bar] injectKeyCode failed', e);
  }
}

export function ControlBar({ serial }: Props) {
  const disabled = !getMirrorSession(serial);

  return (
    <div className="control-bar">
      <button
        type="button"
        className="control-btn"
        title="Back"
        disabled={disabled}
        onClick={() => pressKey(serial, AndroidKeyCode.AndroidBack)}
      >
        Back
      </button>
      <button
        type="button"
        className="control-btn"
        title="Home"
        disabled={disabled}
        onClick={() => pressKey(serial, AndroidKeyCode.AndroidHome)}
      >
        Home
      </button>
      <button
        type="button"
        className="control-btn"
        title="Wake / Power"
        disabled={disabled}
        onClick={() => pressKey(serial, AndroidKeyCode.Power)}
      >
        Wake
      </button>
    </div>
  );
}
