import { inject, ref, type InjectionKey } from 'vue';
import {
  createMemoryFallbackStorage,
  createRetentionStore,
  type RetentionStore,
  type StorageLike,
} from '../../handbook/retentionStore';

export const HANDBOOK_STORE_KEY: InjectionKey<RetentionStore> = Symbol('handbook-store');

let singletonStore: RetentionStore | null = null;
const revision = ref(0);

function getSafeBrowserStorage(): StorageLike {
  if (typeof window !== 'undefined' && typeof window.localStorage !== 'undefined') {
    return window.localStorage;
  }
  return createMemoryFallbackStorage();
}

export function getSharedHandbookStore(): RetentionStore {
  if (!singletonStore) {
    singletonStore = createRetentionStore(getSafeBrowserStorage());
    singletonStore.subscribe(() => {
      revision.value += 1;
    });
  }
  return singletonStore;
}

export function useHandbookStore(explicitStore?: RetentionStore): {
  store: RetentionStore;
  revision: typeof revision;
} {
  const resolved = explicitStore ?? inject(HANDBOOK_STORE_KEY, null) ?? getSharedHandbookStore();
  return { store: resolved, revision };
}
