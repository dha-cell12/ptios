// Minimal store factory compatible with React 18 useSyncExternalStore.
// Framework-agnostic so legacy main.ts can also read/subscribe during migration.

export type Store<T> = {
  getState: () => T;
  setState: (updater: Partial<T> | ((prev: T) => Partial<T>)) => void;
  subscribe: (listener: () => void) => () => void;
};

export function createStore<T extends object>(initial: T): Store<T> {
  let state = initial;
  const listeners = new Set<() => void>();

  const getState = () => state;

  const setState: Store<T>['setState'] = (updater) => {
    const patch = typeof updater === 'function' ? updater(state) : updater;
    let changed = false;
    for (const key of Object.keys(patch) as (keyof T)[]) {
      if (!Object.is(state[key], patch[key])) { changed = true; break; }
    }
    if (!changed) return;
    state = { ...state, ...patch };
    for (const l of listeners) l();
  };

  const subscribe: Store<T>['subscribe'] = (listener) => {
    listeners.add(listener);
    return () => { listeners.delete(listener); };
  };

  return { getState, setState, subscribe };
}
