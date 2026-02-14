import { CacheCleanupManager } from './CacheCleanupManager';
import { CleanupResult } from './types';
import { getLogger, withTiming } from '../../utils';
import { CacheConfig } from '../config/types';

export class CleanupScheduler {
  private readonly TAG = 'CleanupScheduler';
  private readonly log = getLogger(this.TAG);
  private cleanupManager: CacheCleanupManager;
  private isRunning = false;
  // Use platform-agnostic timer handle types (any) to avoid Node-specific typings
  private initialTimer: number | null = null;
  private dailyTimer: number | null = null;
  private disableTimers: boolean = false; // legacy support for constructor debug flag
  // Track current async cleanup run so callers (tests) can await idle
  private currentRun: Promise<CleanupResult> | null = null;

  constructor(cleanupManager: CacheCleanupManager, config?: CacheConfig) {
    this.cleanupManager = cleanupManager;
    if (config?.isDebug) this.disableTimers = true;
  }

  /**
   * 启动定时清理任务
   */
  startScheduledCleanup(): void {
    if (this.initialTimer || this.dailyTimer) return;

    // Track startup cleanup
    this.currentRun = withTiming(`${this.TAG}:startup.performCleanup`, () => this.performCleanup()).finally(() => { this.currentRun = null; });

    if (this.disableTimers) {
      this.log.info('Cache cleanup scheduler started (timers disabled)');
      return;
    }

    // 计算距离下一个凌晨0点的毫秒数
    const now = new Date();
    const nextMidnight = new Date(now);
    nextMidnight.setHours(24, 0, 0, 0);
    const msToMidnight = nextMidnight.getTime() - now.getTime();

    this.initialTimer = setTimeout(() => {
      this.currentRun = withTiming(`${this.TAG}:scheduled.performCleanup`, () => this.performCleanup()).finally(() => { this.currentRun = null; });
      this.dailyTimer = setInterval(() => {
        this.currentRun = withTiming(`${this.TAG}:scheduled.performCleanup`, () => this.performCleanup()).finally(() => { this.currentRun = null; });
      }, 24 * 60 * 60 * 1000);
    }, msToMidnight);

    this.log.info('Cache cleanup scheduler started');
  }

  stopScheduledCleanup(): void {
    if (this.initialTimer) { clearTimeout(this.initialTimer); this.initialTimer = null; }
    if (this.dailyTimer) { clearInterval(this.dailyTimer); this.dailyTimer = null; }
  }

  /**
   * 执行清理（公开方法，可手动调用）
   */
  async performCleanup(): Promise<CleanupResult> {
    if (this.isRunning) {
      this.log.info('Cleanup already in progress, skipping this run');
      const now = Date.now();
      return {
        deletedEvents: 0,
        retainedEvents: 0,
        freedSpace: 0,
        errorCount: 0,
        startTime: now,
        endTime: now,
        duration: 0
      };
    }

    this.isRunning = true;
    try {
      return await this.cleanupManager.performCleanup();
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * 紧急清理（当存储空间严重不足时）
   */
  async emergencyCleanup(): Promise<CleanupResult> {
    this.log.info('Performing emergency cleanup...');
    const result = await withTiming('emergency.performCleanup', () => this.performCleanup());

    // 如果仍然需要更多空间，进行强制清理
    const spaceStatus = await this.cleanupManager.checkSpaceStatus();
    if (spaceStatus.needCleanup) {
      this.log.warn('Storage space still insufficient, performing forced cleanup');
      // 可以在这里实现更激进的清理策略
      await this.cleanupManager.emergencyCleanup();
    }

    return result;
  }

  // Exposed for tests to avoid "Cannot log after tests are done" warnings
  async waitForIdle(): Promise<void> {
    if (this.currentRun) {
      try { await this.currentRun; } catch { /* ignore errors for idle wait */ }
    }
  }
}
