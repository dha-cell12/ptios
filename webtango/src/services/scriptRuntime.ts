import { sleep as sdkSleep, ZxTouchDeviceSdk } from './zxtouchSdk';

export type ScriptRuntimeApi = {
  device: ZxTouchDeviceSdk;
  signal: AbortSignal;
  log: (message: unknown) => void;
};

export async function runBrowserScript(code: string, api: ScriptRuntimeApi): Promise<void> {
  const guardedDevice = new Proxy(api.device as any, {
    get(target, prop, receiver) {
      const value = Reflect.get(target, prop, receiver);
      if (typeof value !== 'function') return value;
      return async (...args: unknown[]) => {
        throwIfAborted(api.signal);
        const result = await value.apply(target, args);
        throwIfAborted(api.signal);
        return result;
      };
    },
  });

  const sleep = (ms: number) => sdkSleep(ms, api.signal);
  const assert = (condition: unknown, message = 'Assertion failed') => {
    if (!condition) throw new Error(message);
  };

  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  const fn = new AsyncFunction('device', 'sleep', 'log', 'assert', 'signal', code);
  await fn(guardedDevice, sleep, api.log, assert, api.signal);
}

function throwIfAborted(signal: AbortSignal) {
  if (signal.aborted) throw new DOMException('Aborted', 'AbortError');
}
