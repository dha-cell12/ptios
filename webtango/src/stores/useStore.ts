import { useSyncExternalStore } from 'react';
import type { Store } from './createStore';

export function useStore<T>(store: Store<T>): T;
export function useStore<T, U>(store: Store<T>, selector: (state: T) => U): U;
export function useStore<T, U>(store: Store<T>, selector?: (state: T) => U) {
  const getSnapshot = () => (selector ? selector(store.getState()) : (store.getState() as unknown as U));
  return useSyncExternalStore(store.subscribe, getSnapshot, getSnapshot);
}
