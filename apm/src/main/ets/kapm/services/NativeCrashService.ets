import { getLogger } from "../utils";
import { APMCore } from "../kapm_core/APMCore";
import { CacheService } from "./CacheService";
import { EventInfoParams, ExceptionInfo, ThreadInfo } from "../kapm_cache/save/types";
import { APMConfigManager } from "../kapm_config/APMConfigManager";
import { FileSystem, getFileSystem } from "../platform/FileSystem";
import { safeJsonParse } from "../utils/safeOperations";
import testNapi from 'libapm.so';

/**
 * Native 崩溃处理服务
 * 负责处理从 native 层拦截的崩溃信号，上传日志后再退出
 */
export class NativeCrashService {
  private readonly TAG = 'NativeCrashService';
  private readonly log = getLogger(this.TAG);
  private cacheService: CacheService;
  private fs: FileSystem;
  private checkInterval: number = 1000; // 1秒检查一次
  private timerId: number | null = null;
  private isProcessing: boolean = false;

  constructor(cacheService: CacheService, fs: FileSystem = getFileSystem()) {
    this.cacheService = cacheService;
    this.fs = fs;
  }

  /**
   * 启动 native 崩溃处理服务
   */
  start() {
    this.log.info('Starting NativeCrashService');

    // 初始化 native 层的崩溃处理
    try {
      testNapi.initCrashHandler();
      this.log.info('Native crash handler initialized');
    } catch (e) {
      this.log.error('Failed to initialize native crash handler', e.message);
    }

    // 启动轮询检查
    this.startPolling();
  }

  /**
   * 停止服务
   */
  stop() {
    if (this.timerId !== null) {
      clearInterval(this.timerId);
      this.timerId = null;
    }
  }

  /**
   * 启动轮询检查待处理的崩溃文件
   */
  private startPolling() {
    this.timerId = setInterval(() => {
      this.checkAndProcessCrash();
    }, this.checkInterval);
  }

  /**
   * 检查并处理崩溃文件
   */
  private async checkAndProcessCrash() {
    if (this.isProcessing) {
      return;
    }

    try {
      // 从 native 层检查是否有待处理的崩溃文件
      const crashFilePath: string | null = testNapi.checkPendingCrash();

      if (crashFilePath && crashFilePath.length > 0) {
        this.log.info(`Found pending crash file: ${crashFilePath}`);
        this.isProcessing = true;
        await this.processCrashFile(crashFilePath);
        this.isProcessing = false;
      }
    } catch (e) {
      this.log.error('Error checking pending crash', e.message);
      this.isProcessing = false;
    }
  }

  /**
   * 处理崩溃文件
   */
  private async processCrashFile(crashFilePath: string) {
    try {
      // 读取崩溃文件
      const crashContent = await this.fs.readFile(crashFilePath);
      const crashData: ESObject = safeJsonParse<ESObject>(crashContent);
      if (!crashData) {
        this.log.error('Failed to parse crash file', crashFilePath);
        return;
      }

      // 转换为 EventInfoParams 格式
      const eventInfo = this.convertToEventInfoParams(crashData);

      // 保存到缓存
      const payload = await this.cacheService.saveToCache({
        dataType: 'nativeCrash',
        uploadInfo: {
          userId: APMConfigManager.getInstance().getDynamicInfo().userId,
          timestamp: Date.now(),
          isBackground: false, // 崩溃时通常不在后台
          sessionId: eventInfo.uuid,
        },
        eventInfo: eventInfo,
        eventTimestamp: eventInfo.time,
      });

      this.log.debug("Saved crash to cache", JSON.stringify({
        cacheDir: payload.cacheDir,
        analy_type: payload.bus._analy_type,
        analy_branch: payload.bus._analy_branch,
      }));

      // 同步上传（阻塞等待上传完成）
      const reportRes = await APMCore.getInstance().reportFile(payload, "NativeCrashService");

      if (reportRes.success) {
        this.log.info('Crash uploaded successfully', JSON.stringify({
          crashFile: crashFilePath,
          cacheDir: payload.cacheDir,
        }));
      } else {
        this.log.error('Crash upload failed', JSON.stringify({
          crashFile: crashFilePath,
          reason: reportRes.reason,
        }));
      }

      // 删除崩溃文件
      try {
        await this.fs.unlink(crashFilePath);
        this.log.debug(`Deleted crash file: ${crashFilePath}`);
      } catch (err) {
        this.log.warn(`Failed to delete crash file: ${crashFilePath}`, err.message);
      }

    } catch (e) {
      this.log.error('Error processing crash file', e.message);
    }
  }

  /**
   * 将 native 崩溃数据转换为 EventInfoParams 格式
   */
  private convertToEventInfoParams(crashData: ESObject): EventInfoParams {
    const now = Date.now();
    const pid = Number(crashData.pid) || 0;

    // 获取 backtrace 数据
    const backtrace: ESObject | undefined = crashData.backtrace;

    // 构建异常信息
    const stackStr = Array.isArray(backtrace)
      ? backtrace.map((item: ESObject) => String(item)).join('\n')
      : (backtrace ? String(backtrace) : '');

    const exception: ExceptionInfo = {
      name: String(crashData.signal_name || 'NativeCrash'),
      message: `Signal ${crashData.signal} (${crashData.signal_name})`,
      stack: stackStr,
    };

    // 构建线程信息
    const stackArray: string[] = Array.isArray(backtrace)
      ? backtrace.map((item: ESObject) => String(item))
      : (backtrace ? [String(backtrace)] : []);

    const threads: ThreadInfo[] = [{
      tid: Number(crashData.tid) || 0,
      stack: stackArray,
    }];

    // 构建 EventInfoParams
    const eventInfo: EventInfoParams = {
      time: Number(crashData.time) || now,
      foreground: true, // 崩溃时假设在前台
      bundle_version: APMConfigManager.getInstance().getConfig().appVersion || 'unknown',
      bundle_name: APMConfigManager.getInstance().getConfig().productName || 'unknown',
      pid: pid,
      uid: 0, // 无法获取，使用默认值
      uuid: this.generateUUID(),
      exception: exception,
      threads: threads,
      crash_type: 'NativeCrash',
    };

    return eventInfo;
  }

  /**
   * 生成 UUID
   */
  private generateUUID(): string {
    return `${Date.now()}_${Math.random().toString(36).substring(2, 15)}`;
  }
}

