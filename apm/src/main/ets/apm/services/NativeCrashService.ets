import { getLogger, withTask } from "../utils";
import { CacheService } from "./CacheService";
import { fs } from "../platform/FileSystem";
import testNapi from 'libapm.so';

/**
 * 崩溃回调函数类型
 * @param crashFilePath 崩溃文件路径
 *
 * @example
* ```typescrip
 * const crashService = new NativeCrashService(cacheService);
 * crashService.onCrash((crashFilePath: string) => {
 *   console.log('崩溃检测到，文件路径:', crashFilePath);
 *   // 可以在这里执行自定义逻辑，比如：
 *   // - 显示用户友好的错误提示
 *   // - 保存额外的应用状态信息
 *   // - 触发自定义的崩溃分析
 * });
 * crashService.start();
 * ```
 */
export type CrashCallback = (crashFilePath: string) => void;

/**
 * Native 崩溃处理服务
 * 负责处理从 native 层拦截的崩溃信号，上传日志后再退出
 *
 * 使用方式：
 * ```typescript
 * const crashService = new NativeCrashService(cacheService);
 *
 * // 可选：设置崩溃回调函数
 * crashService.onCrash((crashFilePath: string) => {
 *   console.log('检测到崩溃:', crashFilePath);
 * });
 *
 * // 启动服务
 * crashService.start();
 * ```
 */
export class NativeCrashService {
  private readonly TAG = 'NativeCrashService';
  private readonly log = getLogger(this.TAG);
  private cacheService: CacheService;
  private checkInterval: number = 50; // 50ms检查一次（快速检测崩溃，实现实时检测）
  private timerId: number | null = null;
  private isProcessing: boolean = false;
  private crashCallback: CrashCallback = () => {
  }

  constructor(cacheService: CacheService) {
    this.cacheService = cacheService;
  }

  /**
   * 设置崩溃回调函数
   * 当检测到崩溃信号时，会调用此回调函数
   * @param callback 回调函数，接收崩溃文件路径作为参数
   */
  onCrash(callback: CrashCallback) {
    this.crashCallback = callback;
    this.log.info('Crash callback registered');
    return this
  }

  /**
   * 启动 native 崩溃处理服务
   */
  start() {
    this.log.info('Starting NativeCrashService');

    // 初始化 native 层的崩溃处理
    try {
      // 1. 设置回调函数
      testNapi.setCallback((message: string) => {
        this.log.info('Native callback invoked with:', message);
        // 可以在这里执行任何 ArkTS 逻辑
      });

      const cacheDir = this.cacheService.getCacheDir();
      testNapi.initNativeCrashHandler(cacheDir, 3);
      this.log.info('Native crash handler initialized with cache dir:', cacheDir);
    } catch (e) {
      this.log.error('Failed to initialize native crash handler', e.message);
    }

    // 启动时立即检查是否有上次崩溃遗留的文件
    // this.checkAndProcessCrash();

    // 启动文件轮询检查
    // this.startPolling();
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
    this.log.info(`Starting crash file polling, interval: ${this.checkInterval}ms`);
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
      // 方式1：检查实时崩溃通知标志（优先级高，实时性好）
      // 注意：基于内存变量，只在当前进程运行期间有效，重启后会丢失
      const notifyResult = testNapi.checkCrashState();
      this.log.debug("Checking crash notify flag: " + JSON.stringify(notifyResult));
      if (notifyResult.detected) {
        this.log.info(`Crash notification detected via signal flag (real-time). Name: ${notifyResult.crashName}, Reason: ${notifyResult.crashReason}`);
        // 从文件标志中获取崩溃文件路径
        const crashFilePath: string | null = testNapi.checkPendingCrash();
        if (crashFilePath && crashFilePath.length > 0) {
          await this.handleCrash(crashFilePath);
        }
        return;
      }

      // 方式2：检查文件标志（作为备份）
      const crashFilePath: string | null = testNapi.checkPendingCrash();
      if (crashFilePath && crashFilePath.length > 0) {
        this.log.info(`Found pending crash file: ${crashFilePath}`);
        await this.handleCrash(crashFilePath);
      }

    } catch (e) {
      this.log.error('Error checking pending crash', e.message);
      this.isProcessing = false;
    }
  }

  /**
   * 处理崩溃（统一处理逻辑）
   */
  private async handleCrash(crashFilePath: string) {
    this.isProcessing = true;

    try {
      // 调用回调函数（总是有默认值）
      try {
        this.log.info('About to execute crash callback');
        this.crashCallback(crashFilePath);
        this.log.info('Crash callback executed successfully');
      } catch (e) {
        this.log.error('Error in crash callback', e.message);
      }

      // await this.processCrashFile(crashFilePath);
    } catch (e) {
      this.log.error('Error handling crash', e.message);
    } finally {
      this.isProcessing = false;
    }
  }


  /**
   * 处理崩溃文件
   */
  // private async processCrashFile(crashFilePath: string) {
  //   try {
  //     // 读取崩溃文件
  //     const crashContent = await fs.readFile(crashFilePath);
  //     const crashData: ESObject = safeJsonParse<ESObject>(crashContent);
  //     if (!crashData) {
  //       this.log.error('Failed to parse crash file', crashFilePath);
  //       return;
  //     }
  //
  //     // 转换为 EventInfoParams 格式
  //     const eventInfo = this.convertToEventInfoParams(crashData);
  //
  //     // 保存到缓存
  //     const payload = await this.cacheService.saveToCache({
  //       dataType: 'nativeCrash',
  //       uploadInfo: {
  //         userId: APMConfigManager.getInstance().getDynamicInfo().userId,
  //         timestamp: Date.now(),
  //         isBackground: false, // 崩溃时通常不在后台
  //         sessionId: eventInfo.uuid,
  //       },
  //       eventInfo: eventInfo,
  //       eventTimestamp: eventInfo.time,
  //     });
  //
  //     this.log.debug("Saved crash to cache", JSON.stringify({
  //       cacheDir: payload.cacheDir,
  //       analy_type: payload.bus._analy_type,
  //       analy_branch: payload.bus._analy_branch,
  //     }));
  //
  //     // 同步上传（阻塞等待上传完成）
  //     const reportRes = await APMCore.getInstance().reportFile(payload, "NativeCrashService");
  //
  //     if (reportRes.success) {
  //       this.log.info('Crash uploaded successfully', JSON.stringify({
  //         crashFile: crashFilePath,
  //         cacheDir: payload.cacheDir,
  //       }));
  //     } else {
  //       this.log.error('Crash upload failed', JSON.stringify({
  //         crashFile: crashFilePath,
  //         reason: reportRes.reason,
  //       }));
  //     }
  //
  //     // 删除崩溃文件
  //     try {
  //       await fs.unlink(crashFilePath);
  //       this.log.debug(`Deleted crash file: ${crashFilePath}`);
  //     } catch (err) {
  //       this.log.warn(`Failed to delete crash file: ${crashFilePath}`, err.message);
  //     }
  //
  //   } catch (e) {
  //     this.log.error('Error processing crash file', e.message);
  //   }
  // }

  /**
   * 将 native 崩溃数据转换为 EventInfoParams 格式
   */
  // private convertToEventInfoParams(crashData: ESObject): EventInfoParams {
  //   const now = Date.now();
  //   const pid = Number(crashData.pid) || 0;
  //
  //   // 获取 backtrace 数据
  //   const backtrace: ESObject | undefined = crashData.backtrace;
  //
  //   // 构建异常信息
  //   const stackStr = Array.isArray(backtrace)
  //     ? backtrace.map((item: ESObject) => String(item)).join('\n')
  //     : (backtrace ? String(backtrace) : '');
  //
  //   const exception: ExceptionInfo = {
  //     name: String(crashData.signal_name || 'NativeCrash'),
  //     message: `Signal ${crashData.signal} (${crashData.signal_name})`,
  //     stack: stackStr,
  //   };
  //
  //   // 构建线程信息
  //   const stackArray: string[] = Array.isArray(backtrace)
  //     ? backtrace.map((item: ESObject) => String(item))
  //     : (backtrace ? [String(backtrace)] : []);
  //
  //   const threads: ThreadInfo[] = [{
  //     tid: Number(crashData.tid) || 0,
  //     stack: stackArray,
  //   }];
  //
  //   // 构建 EventInfoParams
  //   const eventInfo: EventInfoParams = {
  //     time: Number(crashData.time) || now,
  //     foreground: true, // 崩溃时假设在前台
  //     bundle_version: APMConfigManager.getInstance().getConfig().appVersion || 'unknown',
  //     bundle_name: APMConfigManager.getInstance().getConfig().productName || 'unknown',
  //     pid: pid,
  //     uid: 0, // 无法获取，使用默认值
  //     uuid: this.generateUUID(),
  //     exception: exception,
  //     threads: threads,
  //     crash_type: 'NativeCrash',
  //   };
  //
  //   return eventInfo;
  // }

  /**
   * 生成 UUID
   */
  // private generateUUID(): string {
  //   return `${Date.now()}_${Math.random().toString(36).substring(2, 15)}`;
  // }
}