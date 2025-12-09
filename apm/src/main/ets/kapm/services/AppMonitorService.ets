import { ApmEventMonitorBuilder } from "../kapm_data_collection/event/ApmEventMonitorBuilder";
import { EventChannel, EventType } from "../kapm_data_collection/event/EventChannel";
import { getLogger } from "../utils";
import { hiAppEvent } from "@kit.PerformanceAnalysisKit";
import { CacheService } from "./CacheService";
import { EventInfoParams } from "../kapm_cache/save/types";
import { APMConfigManager } from "../kapm_config/APMConfigManager";
import { APMCore } from "../kapm_core/APMCore";
import { FileSystem, getFileSystem } from "../platform/FileSystem";
import { EventsMonitor } from "../kapm_data_collection/event/system/crash/EventsMonitor";

const HIAPPEVENT_LOGPATH = "/data/storage/el2/log/hiappevent/"

export class AppMonitorService {
  private TAG = 'AppMonitorService';
  private log = getLogger(this.TAG);
  private monitor: ApmEventMonitorBuilder
  private cacheService: CacheService;
  private fs: FileSystem;

  constructor(cacheService: CacheService, fs: FileSystem = getFileSystem()) {
    this.fs = fs;
    this.cacheService = cacheService;
    this.monitor = new ApmEventMonitorBuilder();
  }

  start(context: Context) {
    this.log.info('start')
    const eventsMonitor = new EventsMonitor(context)
    // 启动服务的代码
    this.monitor
      .append(eventsMonitor)  // 崩溃
      .build()

    this.listen()
  }

  private listen() {
    // 监听事件的代码
    this.log.info('listen');

    const listener = async (eventType: EventType, eventInfo: hiAppEvent.AppEventInfo) => {
      try {
        this.log.info(`Received event: ${eventType}, time: ${eventInfo.params['time']}`);
        // 处理接收到的事件

        // 1. 保存到缓存
        const eventInfoObj: EventInfoParams = JSON.parse(JSON.stringify(eventInfo.params))
        const dataType = eventType
        const payload = await this.cacheService.saveToCache({
          dataType,
          uploadInfo: {
            userId: APMConfigManager.getInstance().getDynamicInfo().userId,
            timestamp: Date.now(),
            isBackground: !eventInfoObj.foreground,
            sessionId: eventInfoObj.uuid,
          },
          eventInfo: eventInfoObj,
          eventTimestamp: eventInfoObj.time,
        })

        this.log.debug("Saved to cache", JSON.stringify({
          cacheDir: payload.cacheDir,
          analy_type: payload.bus._analy_type,
          analy_branch: payload.bus._analy_branch,
        }))

        // 删除原始日志文件
        this.deleteOriginalLogFiles(eventInfoObj);

        // 2. 上传
        const reportRes = await APMCore.getInstance().reportFile(payload, "AppMonitorService");
        this.log.debug("Report result:", JSON.stringify(reportRes));
      } catch (e) {
        this.log.error('Error handling event:', e);
      }
    };

    EventChannel.getInstance()
      .subscribeAll([EventType.JS_ERROR, EventType.NATIVE_CRASH, EventType.APP_FREEZE], listener);
  }


  private async deleteOriginalLogFiles(eventInfo: EventInfoParams) {
    const external_log = eventInfo.external_log
    const log_over_limit = eventInfo.log_over_limit
    if (external_log && external_log.length > 0) {
      for (const logPath of external_log) {
        try {
          await this.fs.unlink(logPath);
          this.log.debug(`Deleted original log file: ${logPath}`);
        } catch (err) {
          this.log.warn(`Failed to delete log file: ${logPath}`, err);
        }
      }
    }

    if (log_over_limit) {
      await this.fs.clearDir(HIAPPEVENT_LOGPATH)
    }
  }
}