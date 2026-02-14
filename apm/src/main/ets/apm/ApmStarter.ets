import { filterConfig } from "./config/APMConfigManager";
import { APMConfig } from "./config/types";
import { APMCore } from "./core/APMCore";
import { getLogger, withLock, withLockSync, withLongTask } from "./utils";
import { withTimingSync } from "./utils/withTiming";

export class ApmStarter {
  private readonly TAG = 'ApmStarter';
  private readonly log = getLogger(this.TAG);

  static start(context: Context, config: Partial<APMConfig>) {
    withLockSync("ApmStarter:init", () => {
      withTimingSync<void>("ApmStarter:init", () => {
        new ApmStarter().init(config)
      })
    })
  }

  private init(config: Partial<APMConfig>): void {
    this.log.info("Initializing APMCore", JSON.stringify({ isDebug: config.isDebug, buildId: config.buildId }));
    try {
      APMCore.init(config)
        .startCacheServices()
        .startNetConService()
        .onError(this.onCrashHappened(config.isDebug))

      withLongTask('ApmThreadServices', startMonitorServices, filterConfig(config))
        .catch(this.onCrashHappened(config.isDebug, 500));

    } catch (error) {
      this.log.error('Error initializing APMCore:', error.message, error.stack);
    }
  }

  private onCrashHappened(isDebug: boolean = true, ms: number = 0): (reason: Error) => void {
    if (!isDebug) {
      return (_reason: Error) => { /* no-op in non-debug mode */ }
    }
    return (reason: Error) => {
      void withLock<void>("ApmStarter:faultDialog", async () => {
        await new Promise<void>((resolve) => {
          setTimeout(() => {
            AlertDialog.show({
              title: "Crash Happened...",
              message: `Error name: ${reason.name}\nError message: ${reason.message}\nStacktrace:\n${reason.stack}`,
              autoCancel: true,
              alignment: DialogAlignment.Bottom,
              offset: { dx: 0, dy: -20 },
              gridCount: 4,
              cancel: resolve,
            })
          }, ms)
        })
      }, { onLockFailed: 'skip' }).catch(() => {
        // 不影响主流程，避免未处理 Promise 拒绝
      })
    }
  }
}

@Concurrent
function startMonitorServices(config: Partial<APMConfig>) {
  getLogger('ApmStarter').info('Starting APMCore Thread Services');
  APMCore.init(config).startMonitorServices()
}
