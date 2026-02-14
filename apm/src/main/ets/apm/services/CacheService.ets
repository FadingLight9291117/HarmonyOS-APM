import { getFileSystem, FileSystem } from '../platform/FileSystem';
import { CacheCleanupManager } from '../cache/clean/CacheCleanupManager';
import { CacheUseManager } from '../cache/use/CacheUseManager';
import { CleanupResult, SpaceStatus } from '../cache/clean/types';
import { StatsResult, PeekOptions, PeekResult, NextResult, BuildOptions } from '../cache/use/types';
import { getLogger, withTiming } from '../utils';
import { CleanupScheduler } from '../cache/clean/CleanupScheduler';
import { CacheConfigManager } from '../cache/config/CacheConfigManager';
import { APMConfig, UploadInfo } from '../config/types';
import { CacheSaveManager, CacheSaveOptions, SaveCacheResult } from '../cache/save/CacheSaveManager';
import { CrashBranchEnum, ReportAttachment, ReportPayload } from '../types/uploadTypes';
import { CacheConfig } from '../cache/config/types';
import { ReportPayloadBuilder } from '../types/reportPayloadBuilders';
import { EventInfoParams, ThreadInfo } from '../cache/save/types';
import { checkCrashState } from 'libapm.so';
import { APMConfigManager } from '../config/APMConfigManager';
import { buildHiviewJsErrorLog } from '../utils/hiviewLog';
import { buildJsErrorFingerprint } from '../utils/fingerprint';

export enum CacheDataType {
  JsError = 'jsError',
  NativeCrash = 'nativeCrash',
  AppFreeze = 'appFreeze',
}

/**
 * CacheService.saveJsError 入参类型（抽象出来便于复用/统一约束）
 */
export interface SaveJsErrorParams {
  /** 错误名称，例如 UnhandledPromiseRejection / TypeError 等 */
  name: string;
  /** 错误原因/消息 */
  reason: string;
  /** 堆栈字符串 */
  stack: string;
  /** 事件来源标识（用于 extra.source） */
  source?: string;
  /** 是否前台，默认 true */
  foreground?: boolean;
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
  private apmConfig: APMConfig;

  constructor(config: APMConfig) {
    this.apmConfig = config;
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
   * 保存 JS Error（包含未处理 Promise Rejection）到缓存。
   * 该方法只负责“落盘”，不负责上传；上传由上层服务触发。
   */
  async saveJsError(params: SaveJsErrorParams): Promise<ReportPayload> {
    const now = Date.now();
    // 指纹：同类错误（name/reason/stack 归一化后相同）-> 指纹相同
    // 用于聚合统计/去重；事件目录仍然用 eventTimestamp 区分每次发生
    let fingerprint = await buildJsErrorFingerprint({
      name: params.name || 'UnhandledPromiseRejection',
      reason: params.reason || 'Unknown reason',
      stack: params.stack || '',
    });
    if (!fingerprint) {
      // 极端情况下 md5 失败，兜底为随机值，避免写盘失败
      fingerprint = `${now}_${Math.random().toString(36).substring(2, 12)}`;
    }

    const stackLines: string[] = params.stack ? params.stack.split('\n') : [];
    const threads: ThreadInfo[] = [{
      name: 'js',
      tid: 0,
      stack: stackLines,
    }];

    // 为 JS Error 生成一份 external_log（用于落盘并作为附件上传）
    // 先写到 cache 根目录的临时区域，CacheSaveManager 会在保存时复制到事件目录并回写 eventInfo.external_log
    // 统一使用系统临时目录（与 EncryptCompressService 默认 tempDir 保持一致）
    const baseTempDir = '/data/storage/el2/base/temp';
    const tmpDir = this.fs.join(baseTempDir, '.apm_tmp');
    await this.fs.ensureDir(tmpDir);
    const tmpLogPath = this.fs.join(tmpDir, `jsError_${now}_${fingerprint}.log`);
    const tmpLogContent = buildHiviewJsErrorLog({
      now,
      fingerprint,
      name: params.name,
      message: params.reason,
      stack: params.stack,
      foreground: params.foreground ?? true,
      info: {
        brand: this.apmConfig.brand,
        deviceType: this.apmConfig.deviceType,
        buildId: this.apmConfig.buildId,
        osVersion: this.apmConfig.osVersion,
        bundleName: this.apmConfig.bundleName,
        appVersion: this.apmConfig.appVersion,
      }
    });
    await this.fs.writeFile(tmpLogPath, tmpLogContent);

    const eventInfo: EventInfoParams = {
      time: now,
      foreground: params.foreground ?? true,
      bundle_version: this.apmConfig.appVersion || 'unknown',
      bundle_name: this.apmConfig.bundleName || 'unknown',
      pid: 0,
      uid: 0,
      uuid: fingerprint,
      crash_type: 'JsError',
      exception: {
        name: params.name || 'UnhandledPromiseRejection',
        message: params.reason || 'Unknown reason',
        stack: params.stack || '',
      },
      threads: threads,
      external_log: [tmpLogPath],
    };

    try {
      return await this.saveToCache({
        dataType: CacheDataType.JsError,
        uploadInfo: {
          userId: APMConfigManager.getInstance().getDynamicInfo().userId,
          timestamp: now,
          isBackground: false,
          sessionId: fingerprint,
        },
        eventInfo,
        eventTimestamp: now,
        extra: {
          'source': params.source ?? 'onUnhandledRejection',
        }
      });
    } finally {
      // 清理临时文件（cache 内会有拷贝后的 log）
      try {
        await this.fs.unlink(tmpLogPath);
      } catch (e) {
        // ignore
      }
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

    // 仅 NativeCrash 才读取 native crash 状态；JsError 不应被 native 状态污染
    let nativeCrashName: string | undefined = undefined;
    let nativeCrashReason: string | undefined = undefined;
    if (dataType === CacheDataType.NativeCrash) {
      const nativeCrashStateResult = checkCrashState();
      this.log.warn("Native crash state:", JSON.stringify(nativeCrashStateResult));
      nativeCrashName = nativeCrashStateResult.crashName;
      nativeCrashReason = nativeCrashStateResult.crashReason;
    }

    // 使用 ReportPayloadBuilder 构建 payload
    this.payloadBuilder
      .buildBaseInfo(uploadInfo)
      .buildCrashBusInfo(dataType === CacheDataType.JsError ? CrashBranchEnum.JsError : CrashBranchEnum.NativeCrash,
        eventTimestamp, {
          fingerprint: eventInfo.uuid,
          crash_type: dataType,
          crash_name: nativeCrashName || eventInfo.exception?.name || 'Unknown error',
          crash_reason: nativeCrashReason || eventInfo.exception?.message || 'Unknown reason'
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
