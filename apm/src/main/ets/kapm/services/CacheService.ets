import { getFileSystem, FileSystem } from '../platform/FileSystem';
import { CacheCleanupManager } from '../kapm_cache/clean/CacheCleanupManager';
import { CacheUseManager } from '../kapm_cache/use/CacheUseManager';
import { CleanupResult, SpaceStatus } from '../kapm_cache/clean/types';
import { StatsResult, PeekOptions, PeekResult, NextResult, BuildOptions } from '../kapm_cache/use/types';
import { getLogger, withTiming } from '../utils';
import { CleanupScheduler } from '../kapm_cache/clean/CleanupScheduler';
import { CacheConfigManager } from '../kapm_cache/config/CacheConfigManager';
import { APMConfig, UploadInfo } from '../kapm_config/types';
import { CacheSaveManager, CacheSaveOptions, SaveCacheResult } from '../kapm_cache/save/CacheSaveManager';
import { CrashBranchEnum, ReportAttachment, ReportPayload } from '../types/uploadTypes';
import { CacheConfig } from '../kapm_cache/config/types';
import { ReportPayloadBuilder } from '../types/reportPayloadBuilders';
import { EventInfoParams } from '../kapm_cache/save/types';
import { checkCrashState } from 'libapm.so';

export enum CacheDataType {
  JsError = 'jsError',
  NativeCrash = 'nativeCrash',
  AppFreeze = 'appFreeze',
}

export class CacheService {
  private readonly TAG = 'CacheService';
  private readonly log = getLogger(this.TAG);
  private fs: FileSystem = getFileSystem();
  private cleanupManager: CacheCleanupManager;
  private useManager: CacheUseManager;
  private scheduler: CleanupScheduler;
  private cacheConfig: CacheConfig;
  private saveManager: CacheSaveManager;
  private payloadBuilder: ReportPayloadBuilder;

  constructor(config: APMConfig) {
    // Initialize integrated managers pointing at same cache directory (bridge from APMConfig)
    // Use CacheConfigManager for validation and config merging
    const configManager = new CacheConfigManager(config);
    this.cacheConfig = configManager.getConfig();
    this.cleanupManager = new CacheCleanupManager(this.cacheConfig, this.fs);
    this.useManager = new CacheUseManager(this.cacheConfig, this.fs);
    this.scheduler = new CleanupScheduler(this.cleanupManager, this.cacheConfig);
    this.saveManager = new CacheSaveManager(this.cacheConfig, this.fs);
    this.payloadBuilder = new ReportPayloadBuilder(config);
  }

  getCacheDir(): string {
    return this.cacheConfig.cacheDir;
  }

  /**
   * 保存报告载荷到缓存
   * @param options 缓存保存选项
   * @returns 保存的报告载荷
   */
  async saveToCache(options: CacheSaveOptions): Promise<ReportPayload> {
    try {
      return withTiming(`${this.TAG}:saveToCache`, async () => {
        this.useManager.reset(); // 重置 UseManager 索引，确保新保存的事件可见
        switch (options.dataType) {
          case CacheDataType.JsError:
            return this.saveCrashReport(CacheDataType.JsError, options.eventInfo, options.uploadInfo, options.extra);
          case CacheDataType.NativeCrash:
            return this.saveCrashReport(CacheDataType.NativeCrash, options.eventInfo, options.uploadInfo,
              options.extra);
          case CacheDataType.AppFreeze:
            return this.saveAppFreezeReport(options.dataType, options.eventInfo, options.uploadInfo, options.extra);
          default:
            throw new Error(`Unsupported data type: ${options.dataType}`);
        }
      });
    } catch (e) {
      this.log.error(`Error in saveToCache: ${e} ${e.stack}`);
      throw e as Error;
    }
  }

  /**
   * 通用的构建 payload 方法
   */
  private buildPayloadWithAttachments(
    uploadInfo: UploadInfo,
    saveResult: SaveCacheResult,
    extra?: Record<string, string | number | boolean>
  ): ReportPayload {
    return (
    this.payloadBuilder
      .buildBaseInfo(uploadInfo)
      .buildPayload({
        cacheDir: saveResult.cacheDir,
        attachments: saveResult.attachments.map<ReportAttachment>(attachment => ({
          name: this.fs.basename(attachment),
          path: attachment,
        })),
        extra,
      })
    );
  }

  /**
   * 便捷方法：保存崩溃报告到缓存
   */
  private async saveCrashReport(
    dataType: string,
    eventInfo: EventInfoParams,
    uploadedInfo: Partial<UploadInfo> = {},
    extra?: Record<string, string | number | boolean>,
  ): Promise<ReportPayload> {
    const uploadInfo = this.buildUploadInfo(eventInfo, uploadedInfo);
    const eventTimestamp = eventInfo.time;

    const saveResult = await this.saveManager.saveToCache({
      dataType,
      uploadInfo,
      eventTimestamp,
      eventInfo,
      extra,
    });

    const nativeCrashStateResult = checkCrashState();
    this.log.warn("Native crash state:", JSON.stringify(nativeCrashStateResult));

    // 使用 ReportPayloadBuilder 构建 payload
    this.payloadBuilder
      .buildBaseInfo(uploadInfo)
      .buildCrashBusInfo(dataType === CacheDataType.JsError ? CrashBranchEnum.JsError : CrashBranchEnum.NativeCrash,
        eventTimestamp, {
          fingerprint: eventInfo.uuid,
          crash_type: dataType,
          crash_name: nativeCrashStateResult.crashName || eventInfo.exception?.name || 'Unknown error',
          crash_reason: nativeCrashStateResult.crashReason || eventInfo.exception?.message || 'Unknown reason'
        })

    return this.buildPayloadWithAttachments(uploadInfo, saveResult, extra);
  }

  /**
   * 便捷方法：保存应用冻屏报告到缓存
   */
  private async saveAppFreezeReport(
    dataType: string,
    eventInfo: EventInfoParams,
    uploadedInfo: Partial<UploadInfo> = {},
    extra?: Record<string, string | number | boolean>,
  ): Promise<ReportPayload> {
    const uploadInfo = this.buildUploadInfo(eventInfo, uploadedInfo);
    const eventTimestamp = eventInfo.time;

    const saveResult = await this.saveManager.saveToCache({
      dataType,
      uploadInfo,
      eventTimestamp,
      eventInfo,
      extra,
    });

    // 使用 ReportPayloadBuilder 构建 payload
    this.payloadBuilder
      .buildBaseInfo(uploadInfo)
      .buildAppFreezeBusInfo(eventTimestamp, {
        fingerprint: eventInfo.uuid,
        freeze_name: eventInfo.exception?.name || 'Unknown',
        freeze_reason: eventInfo.exception?.message || 'Unknown reason'
      })

    return this.buildPayloadWithAttachments(uploadInfo, saveResult, extra);
  }

  private buildUploadInfo(eventInfo: EventInfoParams, uploadedInfo: Partial<UploadInfo> = {}): UploadInfo {
    return {
      userId: uploadedInfo.userId,
      timestamp: eventInfo.time,
      processId: eventInfo.pid?.toString() || '',
      threadId: eventInfo.threads?.[0]?.tid?.toString() || '',
      isBackground: !eventInfo.foreground,
      sessionId: uploadedInfo.sessionId,
      network: uploadedInfo.network,
      carrier: uploadedInfo.carrier,
      region: uploadedInfo.region,
    };
  }


  /**
   * 启动定时清理任务
   */
  startScheduledCleanup(): void {
    // In debug/test mode disable timers to avoid lingering handles in tests
    this.scheduler.startScheduledCleanup();
  }

  /**
   * 执行清理任务
   */
  async performCleanup(): Promise<CleanupResult> {
    return withTiming(`${this.TAG}:performCleanup`, () => this.cleanupManager.performCleanup());
  }

  // Added: allow stopping timers (use in tests to avoid open handles)
  stopScheduledCleanup(): void {
    this.scheduler.stopScheduledCleanup();
  }

  async waitForIdle(): Promise<void> {
    await this.scheduler.waitForIdle();
  }

  // --- Integrated cleanup manager delegation ---
  checkSpaceStatus(): Promise<SpaceStatus> {
    return this.cleanupManager.checkSpaceStatus();
  }

  // --- Integrated use manager delegation (lazy build by manager itself) ---
  /**
   * 构建缓存使用索引
   * @param options.skipUploaded 是否跳过已上传的事件（存在 .uploaded 标记文件）
   */
  buildUsageIndex(options?: BuildOptions) {
    return this.useManager.build(options);
  }

  nextCacheGroup(): Promise<NextResult | null> {
    return this.useManager.next();
  }

  peekCache(limitOrOptions: number | PeekOptions, includeSizeLegacy?: boolean): Promise<PeekResult> {
    return this.useManager.peek(limitOrOptions, includeSizeLegacy);
  }

  stats(calcSize = false): Promise<StatsResult> {
    return this.useManager.stats(calcSize);
  }

  refresh(calcSize = false) {
    return this.useManager.refresh(calcSize);
  }
}
