import { CacheConfig, CleanupPriority } from './types';

export const defaultCacheConfig: CacheConfig = {
  cacheDir: './files/apm_cache/',
  retentionDays: 7,
  maxEventsPerDir: 100, // per dataType event count limit
  maxTotalSize: 100 * 1024 * 1024,
  spaceCleanupOvershootFactor: 1.2,
  enableUploadedEventsCleanup: false,
  /**
   * dataTypes 说明：
   * - jsError / nativeCrash 共享物理目录 group: 'crash' (形如 crash/jsError_1695868800123/...)
   * - appFreeze 单独物理目录 group: 'app_freeze' (形如 app_freeze/appFreeze_1695868800456/...)
   */
  dataTypes: [
    { name: 'jsError', priority: CleanupPriority.HIGH, group: 'crash' },
    { name: 'nativeCrash', priority: CleanupPriority.HIGH, group: 'crash' },
    { name: 'appFreeze', priority: CleanupPriority.NORMAL, group: 'app_freeze' },
  ],
};
