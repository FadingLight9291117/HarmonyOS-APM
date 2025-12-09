import { getLogger, safeFileOperation, withTiming, humanizeBytes, humanizeDuration } from '../../utils';
import { CleanupResult, SpaceStatus, BatchDeleteResult } from './types';
import { defaultCacheConfig } from '../config/CacheConfig';
import { getFileSystem, FileSystem } from '../../platform/FileSystem';
import { CacheConfig, DataTypeEntry } from '../config/types';
import { scanEvents } from '../scan/scanEvents';
import { EventInfo, EventScanOptions } from '../scan/types';
import { CacheValidation } from './validation';

export class CacheCleanupManager {
  private readonly TAG = 'CacheCleanupManager';
  private readonly log = getLogger(this.TAG);
  private readonly fs: FileSystem;
  private config: CacheConfig;
  private readonly overshootFactor: number;
  private dataTypePriority: Record<string, number> = {};
  private readonly DATA_TYPES: DataTypeEntry[];

  private readonly cacheDir: string;
  private readonly retentionMs: number;
  private readonly maxEventsPerDir: number; // prefer config.maxEventsPerDir (event count limit)
  private readonly maxTotalSize: number;
  private readonly enableUploadedEventsCleanup: boolean;

  constructor(cfg?: CacheConfig, fsImpl: FileSystem = getFileSystem()) {
    this.config = cfg ?? defaultCacheConfig;
    this.fs = fsImpl;
    this.cacheDir = this.config.cacheDir;
    this.retentionMs = this.config.retentionDays * 24 * 60 * 60 * 1000;
    this.maxEventsPerDir = this.config.maxEventsPerDir; // legacy maxFilesPerDir removed
    this.maxTotalSize = this.config.maxTotalSize;
    this.enableUploadedEventsCleanup = !!this.config.enableUploadedEventsCleanup;
    this.DATA_TYPES = (this.config.dataTypes || []).map(d => typeof d === 'string' ? { name: d, priority: 3, group: d } : d);
    for (const d of this.DATA_TYPES) this.dataTypePriority[d.name] = d.priority ?? 3;
    this.overshootFactor = this.config.spaceCleanupOvershootFactor ?? 1.2;
  }

  async performCleanup(): Promise<CleanupResult> {
    const result: CleanupResult = {
      deletedEvents: 0, retainedEvents: 0, freedSpace: 0, errorCount: 0,
      startTime: Date.now(), endTime: 0, phases: {}
    };

    try {
      this.log.info('Starting cache cleanup process...');

      // 执行清理阶段并合并结果
      await this.runPhase(result, 'orphanedDirectories', () => this.cleanupOrphanedDirectories());    // 1. 清理孤儿组、孤儿目录、空目录和孤儿文件
      await this.runPhase(result, 'invalidEvents', () => this.cleanupInvalidEvents());                // 2. 清理无效事件
      await this.runPhase(result, 'expiredEvents', () => this.cleanupExpiredEvents());                // 3. 清理过期事件

      if (this.enableUploadedEventsCleanup) {
        await this.runPhase(result, 'uploadedEvents', () => this.cleanupUploadedEvents());            // 4. 清理已上传事件
      }

      for (const dt of this.DATA_TYPES) {
        await this.runPhase(result, `dir:${dt.name}`, () => this.enforceMaxFilesInDir(dt.name));      // 5. 强制单目录事件数限制
      }

      const spaceStatus = await withTiming(`${this.TAG}:checkSpaceStatus`, () => this.checkSpaceStatus());
      if (spaceStatus.needCleanup) {
        await this.runPhase(result, 'space', () => this.cleanupForSpace(spaceStatus.overSize));       // 6. 清理以满足总空间限制
      }

      // 最终统计剩余事件数
      try {
        const finalScan = await scanEvents(this.cacheDir, this.DATA_TYPES, { includeStat: false }, this.fs);
        result.retainedEvents = finalScan.events.length;
      } catch (e) {
        this.log.warn('Final retainedEvents scan failed:', e);
      }
    } catch (e) {
      this.log.error('Cache cleanup process failed:', e);
      result.errorCount++;
    } finally {
      result.endTime = Date.now();
      result.duration = result.endTime - (result.startTime || result.endTime);
      this.logCleanupResult(result);
    }
    return result;
  }

  private async runPhase(result: CleanupResult, phaseName: string, fn: () => Promise<CleanupResult>): Promise<void> {
    const phaseResult = await withTiming(`${this.TAG}:${phaseName}`, fn);
    result.phases![phaseName] = phaseResult;
    this.merge(result, phaseResult);
  }

  /**
   * 清理孤儿组、孤儿目录、空目录和孤儿文件
   * 1. 孤儿组：不在配置 dataTypes 中的组目录
   * 2. 孤儿目录：格式不符合标准的事件目录（如 jsError_20251015174348）
   * 3. 空事件目录：有效格式但完全没有文件的事件目录
   * 4. 孤儿文件：直接存在于组目录下的文件（应该在事件目录内）
   */
  private async cleanupOrphanedDirectories(): Promise<CleanupResult> {
    const res: CleanupResult = { deletedEvents: 0, retainedEvents: 0, freedSpace: 0, errorCount: 0 } ;
    let orphanedFilesCount = 0;
    let orphanedGroupsCount = 0;

    this.log.info('Starting orphaned cleanup...');

    const validGroupNames = new Set(this.DATA_TYPES.map(dt => dt.group || dt.name));
    const cacheRootEntries = await safeFileOperation(() => this.fs.readdir(this.cacheDir));

    if (Array.isArray(cacheRootEntries)) {
      for (const entry of cacheRootEntries as string[]) {
        const entryPath = this.fs.join(this.cacheDir, entry);
        const isDir = await safeFileOperation(() => this.fs.isDirectory(entryPath));

        if (!isDir) {
          // 缓存根目录下不应该有文件
          const fileSize = await safeFileOperation(() => this.getFileSize(entryPath));
          const deleted = await safeFileOperation(() => this.fs.unlink(entryPath));

          if (deleted !== null && fileSize !== null) {
            orphanedFilesCount++;
            res.freedSpace += fileSize;
            this.log.info(`Deleted orphaned file in cache root: ${entry}, freed ${humanizeBytes(fileSize)}`);
          } else {
            res.errorCount++;
          }
          continue;
        }

        // 检查是否为有效的组目录
        if (!validGroupNames.has(entry)) {
          this.log.warn(`Found orphaned group: ${entry}`);
          const freedSize = await this.deleteDirectoryRecursive(entryPath);

          if (freedSize !== null) {
            orphanedGroupsCount++;
            res.deletedEvents++;
            res.freedSpace += freedSize;
            this.log.info(`Deleted orphaned group: ${entry}, freed ${humanizeBytes(freedSize)}`);
          } else {
            res.errorCount++;
          }
        }
      }
    }

    // 步骤 2: 清理有效组内的孤儿目录和孤儿文件
    for (const dt of this.DATA_TYPES) {
      const groupDir = this.fs.join(this.cacheDir, dt.group || dt.name);
      const groupExists = await safeFileOperation(() => this.fs.exists(groupDir));
      if (!groupExists) continue;

      const dirList = await safeFileOperation(() => this.fs.readdir(groupDir));
      if (!Array.isArray(dirList)) {
        this.log.warn(`Failed to read directory: ${groupDir}`);
        res.errorCount++;
        continue;
      }

      for (const entry of dirList as string[]) {
        const entryPath = this.fs.join(groupDir, entry);
        const isDir = await safeFileOperation(() => this.fs.isDirectory(entryPath));

        if (isDir) {
          if (!CacheValidation.isValidEventDir(entry)) {
            // 无效格式的目录
            const freedSize = await this.deleteDirectoryRecursive(entryPath);
            if (freedSize !== null) {
              res.deletedEvents++;
              res.freedSpace += freedSize;
              this.log.info(`Deleted invalid dir: ${entry}, freed ${humanizeBytes(freedSize)}`);
            } else {
              res.errorCount++;
            }
          } else {
            // 检查是否为空目录
            const eventFiles = await safeFileOperation(() => this.fs.readdir(entryPath));
            if (Array.isArray(eventFiles) && eventFiles.length === 0) {
              const rmResult = await safeFileOperation(() => this.fs.rmdir(entryPath));
              if (rmResult !== null) {
                res.deletedEvents++;
                this.log.info(`Deleted empty dir: ${entry}`);
              } else {
                res.errorCount++;
              }
            }
          }
        } else {
          // 组目录下不应该有文件
          const fileSize = await safeFileOperation(() => this.getFileSize(entryPath));
          const deleted = await safeFileOperation(() => this.fs.unlink(entryPath));

          if (deleted !== null && fileSize !== null) {
            orphanedFilesCount++;
            res.freedSpace += fileSize;
            this.log.info(`Deleted orphaned file: ${entry}, freed ${humanizeBytes(fileSize)}`);
          } else {
            res.errorCount++;
          }
        }
      }
    }

    this.log.info(`cleanupOrphanedDirectories deletedGroups=${orphanedGroupsCount} deletedEvents=${res.deletedEvents} deletedFiles=${orphanedFilesCount} freed=${humanizeBytes(res.freedSpace)} errors=${res.errorCount}`);
    return res;
  }

  private async cleanupInvalidEvents(): Promise<CleanupResult> {
    const res: CleanupResult = { deletedEvents: 0, retainedEvents: 0, freedSpace: 0, errorCount: 0 } ;
    const scan = await scanEvents(this.cacheDir, this.DATA_TYPES, { includeStat: true }, this.fs);

    for (const ev of scan.events) {
      const invalidReason = await this.validateEvent(ev);

      if (invalidReason) {
        const freed = await this.deleteEventAndCalc(ev, 'invalid-event');
        if (freed !== null) {
          res.deletedEvents++;
          res.freedSpace += freed;
          this.log.info(`Deleted invalid event (${invalidReason}): ${ev.base}`);
        } else {
          res.errorCount++;
        }
      }
    }

    this.log.info(`cleanupInvalidEvents deleted=${res.deletedEvents} freed=${humanizeBytes(res.freedSpace)} errors=${res.errorCount}`);
    return res;
  }

  private async cleanupExpiredEvents(): Promise<CleanupResult> {
    const res: CleanupResult = { deletedEvents: 0, retainedEvents: 0, freedSpace: 0, errorCount: 0 };
    const now = Date.now();
    const scan = await scanEvents(this.cacheDir, this.DATA_TYPES, { includeStat: true, includeUploadedMarker: true }, this.fs);

    const expiredEvents = scan.events
      .filter(ev => now - ev.createTime > this.retentionMs)
      .sort((a, b) => {
        const uploadedDiff = (b.hasUploaded ? 1 : 0) - (a.hasUploaded ? 1 : 0);
        return uploadedDiff !== 0 ? uploadedDiff : a.createTime - b.createTime;
      });

    for (const ev of expiredEvents) {
      const freed = await this.deleteEventAndCalc(ev, ev.hasUploaded ? 'expired-uploaded' : 'expired');
      if (freed !== null) {
        res.deletedEvents++;
        res.freedSpace += freed;
        this.log.info(`Deleted expired event: ${ev.base}`);
      } else {
        res.errorCount++;
      }
    }

    this.log.info(`cleanupExpiredEvents deleted=${res.deletedEvents} freed=${humanizeBytes(res.freedSpace)} errors=${res.errorCount}`);
    return res;
  }

  /**
   * 可选：清理所有已上传的事件（带 .uploaded 标记），不论是否达到过期条件。
   * 适用于希望在成功上报后尽快释放空间的场景。
   */
  private async cleanupUploadedEvents(): Promise<CleanupResult> {
    const res: CleanupResult = { deletedEvents: 0, retainedEvents: 0, freedSpace: 0, errorCount: 0 } ;
    const scan = await scanEvents(this.cacheDir, this.DATA_TYPES, { includeStat: true, includeUploadedMarker: true }, this.fs);
    const uploaded = scan.events.filter(ev => ev.hasUploaded);
    if (uploaded.length === 0) {
      res.retainedEvents = scan.events.length; // 全部保留
      return res;
    }
    for (const ev of uploaded) {
      const freed = await this.deleteEventAndCalc(ev, 'uploaded');
      if (freed == null) { res.errorCount++; continue; }
      res.deletedEvents++; res.freedSpace += freed;
    }
    // retained: 非 uploaded 事件数量
    res.retainedEvents = scan.events.length - res.deletedEvents;
    this.log.info(`cleanupUploadedEvents deleted=${res.deletedEvents} retained=${res.retainedEvents} freed=${humanizeBytes(res.freedSpace)} errors=${res.errorCount}`);
    return res;
  }

  private async enforceMaxFilesInDir(dataType: string): Promise<CleanupResult> {
    const res: CleanupResult = { deletedEvents: 0, retainedEvents: 0, freedSpace: 0, errorCount: 0 } ;
    const scan = await scanEvents(this.cacheDir, this.DATA_TYPES, { includeStat: true, includeUploadedMarker: true }, this.fs);
    const eventsOfType = scan.events.filter(ev => ev.dataType === dataType);

    if (eventsOfType.length <= this.maxEventsPerDir) {
      res.retainedEvents = eventsOfType.length;
      return res;
    }

    const sorted = eventsOfType.sort((a, b) => (b.priority - a.priority) || (a.createTime - b.createTime));
    const excessCount = eventsOfType.length - this.maxEventsPerDir;

    for (const ev of sorted.slice(0, excessCount)) {
      const freed = await this.deleteEventAndCalc(ev, 'max-events-limit');
      if (freed !== null) {
        res.deletedEvents++;
        res.freedSpace += freed;
        this.log.info(`Deleted event due to limit: ${ev.base}`);
      } else {
        res.errorCount++;
      }
    }

    res.retainedEvents = eventsOfType.length - res.deletedEvents;
    return res;
  }

  private async cleanupForSpace(overSize: number): Promise<CleanupResult> {
    const res: CleanupResult = { deletedEvents: 0, retainedEvents: 0, freedSpace: 0, errorCount: 0 };
    const scan = await scanEvents(this.cacheDir, this.DATA_TYPES, { includeStat: true, includeUploadedMarker: true }, this.fs);

    const sorted = scan.events.sort((a, b) => {
      const uploadedDiff = (b.hasUploaded ? 1 : 0) - (a.hasUploaded ? 1 : 0);
      if (uploadedDiff !== 0) return uploadedDiff;
      return (b.priority - a.priority) || (a.createTime - b.createTime);
    });

    let freed = 0;
    const target = overSize * this.overshootFactor;

    for (const ev of sorted) {
      if (freed >= target) break;

      const freedSize = await this.deleteEventAndCalc(ev, 'space');
      if (freedSize !== null) {
        freed += freedSize;
        res.deletedEvents++;
        res.freedSpace += freedSize;
        this.log.info(`Deleted event for space: ${ev.base}`);
      } else {
        res.errorCount++;
      }
    }

    res.retainedEvents = scan.events.length - res.deletedEvents;
    return res;
  }


  private async validateEvent(ev: EventInfo): Promise<string | null> {
    const jsonFiles = ev.files.filter(f => f.path.endsWith('.json'));
    const metaFiles = ev.files.filter(f => f.path.endsWith('.meta'));

    if (jsonFiles.length === 0) return 'missing .json';
    if (metaFiles.length === 0) return 'missing .meta';

    // 检查 JSON 文件有效性
    for (const f of [...jsonFiles, ...metaFiles]) {
      const content = await safeFileOperation(() => this.fs.readFile(f.path));
      if (content === null) return `cannot read ${this.fs.basename(f.path)}`;

      try {
        JSON.parse(content as string);
      } catch {
        return `invalid JSON in ${this.fs.basename(f.path)}`;
      }
    }

    return null;
  }

  async checkSpaceStatus(): Promise<SpaceStatus> {
    // Include uploaded events in space accounting so they can trigger space cleanup
    const scan = await scanEvents(this.cacheDir, this.DATA_TYPES, { includeStat: true, includeUploadedMarker: true }, this.fs);
    const totalSize = scan.events.reduce((a, e) => a + e.files.reduce((s, f) => s + (f.size || 0), 0), 0);
    return { totalSize, needCleanup: totalSize > this.maxTotalSize, overSize: Math.max(0, totalSize - this.maxTotalSize) };
  }

  /**
   * 删除指定的事件（根据 eventBase）
   * @param eventBase 事件目录名，如 'jsError_1695868800123'
   * @param dataType 可选的数据类型，用于优化查找
   * @returns 释放的空间大小（字节），失败返回 null
   */
  async deleteEventByBase(eventBase: string, dataType?: string): Promise<number | null> {
    const scanOpts: EventScanOptions = { includeStat: true };
    const scan = await scanEvents(this.cacheDir, this.DATA_TYPES, scanOpts, this.fs);

    // 查找匹配的事件
    const event = scan.events.find(ev =>
    ev.base === eventBase && (!dataType || ev.dataType === dataType)
    );

    if (!event) {
      this.log.warn(`Event not found: ${eventBase}${dataType ? ` (type: ${dataType})` : ''}`);
      return null;
    }

    return await this.deleteEventAndCalc(event, 'manual-delete');
  }

  async deleteEventsByBases(eventBases: string[]): Promise<BatchDeleteResult> {
    const result: BatchDeleteResult = { deleted: 0, failed: [] as string[], freedSpace: 0 };

    for (const base of eventBases) {
      const freed = await this.deleteEventByBase(base);
      if (freed !== null) {
        result.deleted++;
        result.freedSpace += freed;
        this.log.info(`Manually deleted: ${base}, freed ${humanizeBytes(freed)}`);
      } else {
        result.failed.push(base);
      }
    }

    this.log.info(`Batch delete: deleted=${result.deleted} failed=${result.failed.length} freed=${humanizeBytes(result.freedSpace)}`);
    return result;
  }

  // 删除整个事件，并返回释放空间；flat 模式下不调用
  private async deleteEventAndCalc(ev: EventInfo, reason: string): Promise<number | null> {
    let total = 0;
    // 先删除所有文件
    for (const f of ev.files) {
      const sz = await safeFileOperation(() => this.getFileSize(f.path));
      const del = await safeFileOperation(() => this.fs.unlink(f.path));
      if (sz == null || del === null) { return null; }
      total += sz as number;
    }

    // 删除事件文件夹
    if (ev.files.length > 0) {
      const eventDir = this.fs.parent(ev.files[0].path);
      const rmDirResult = await safeFileOperation(() => this.fs.rmdir(eventDir));
      if (rmDirResult === null) {
        this.log.warn(`Failed to remove event directory: ${eventDir}`);
      }
    }

    this.log.info(`Deleted event (${reason}): ${ev.base}`, JSON.stringify({ freed: humanizeBytes(total) }));
    return total;
  }

  /**
   * 递归删除目录及其所有内容，并计算释放的空间
   * @param dirPath 要删除的目录路径
   * @returns 释放的字节数，失败返回 null
   */
  private async deleteDirectoryRecursive(dirPath: string): Promise<number | null> {
    let totalSize = 0;

    try {
      // 读取目录内容
      const entries = await safeFileOperation(() => this.fs.readdir(dirPath));
      if (!Array.isArray(entries)) return null;

      // 删除所有文件和子目录
      for (const entry of entries as string[]) {
        const fullPath = this.fs.join(dirPath, entry);

        // 检查是否为目录
        const isDir = await safeFileOperation(() => this.fs.isDirectory(fullPath));

        if (isDir) {
          // 是子目录，递归删除
          const subDirSize = await this.deleteDirectoryRecursive(fullPath);
          if (subDirSize === null) return null;
          totalSize += subDirSize;
        } else {
          // 是文件，获取大小并删除
          const fileSize = await safeFileOperation(() => this.getFileSize(fullPath));
          if (fileSize === null) return null;

          const deleted = await safeFileOperation(() => this.fs.unlink(fullPath));
          if (deleted === null) return null;

          totalSize += fileSize;
        }
      }

      // 删除空目录本身
      const rmDirResult = await safeFileOperation(() => this.fs.rmdir(dirPath));
      if (rmDirResult === null) {
        this.log.warn(`Failed to remove directory: ${dirPath}`);
        return null;
      }

      return totalSize;
    } catch (error) {
      this.log.error(`Error deleting directory recursively: ${dirPath}`, error);
      return null;
    }
  }

  public async emergencyCleanup(): Promise<CleanupResult> {
    this.log.warn('Performing emergency cleanup...');
    const result: CleanupResult = { deletedEvents: 0, retainedEvents: 0, freedSpace: 0, errorCount: 0 };

    try {
      const scan = await scanEvents(this.cacheDir, this.DATA_TYPES, { includeStat: true }, this.fs);

      for (const ev of scan.events) {
        let sizeFreed = 0;
        let hasError = false;

        for (const f of ev.files) {
          const fileSize = await safeFileOperation(() => this.getFileSize(f.path));
          const deleted = await safeFileOperation(() => this.fs.unlink(f.path));

          if (fileSize !== null && deleted !== null) {
            sizeFreed += fileSize;
          } else {
            hasError = true;
          }
        }

        result.freedSpace += sizeFreed;
        if (hasError) {
          result.errorCount++;
        } else if (sizeFreed > 0) {
          result.deletedEvents++;
        }
      }
    } catch (error) {
      this.log.error('Emergency cleanup failed:', error);
      result.errorCount++;
    } finally {
      this.logCleanupResult(result);
    }
    return result;
  }

  private merge(target: CleanupResult, src: CleanupResult) {
    // 只累计删除/空间/错误统计；retainedEvents 最终统一计算，避免阶段间重复累计
    target.deletedEvents += src.deletedEvents;
    target.freedSpace += src.freedSpace;
    target.errorCount += src.errorCount;
  }


  private logCleanupResult(result: CleanupResult): void {
    this.log.info('Cache cleanup completed:', JSON.stringify({
      deletedEvents: result.deletedEvents,
      retainedEvents: result.retainedEvents,
      freedSpace: humanizeBytes(result.freedSpace || 0),
      errorCount: result.errorCount,
      duration: humanizeDuration(result.duration)
    }));
  }

  /**
   * 获取文件大小
   */
  private async getFileSize(p: string): Promise<number | null> {
    try {
      const st = await this.fs.stat(p);
      return st.size;
    } catch {
      return null;
    }
  }
}