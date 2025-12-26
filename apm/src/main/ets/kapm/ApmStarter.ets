import { filterConfig } from "./kapm_config/APMConfigManager";
import { APMConfig } from "./kapm_config/types";
import { APMCore } from "./kapm_core/APMCore";
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
        .onError(error => {
          // this.log.error('Error in APMCore Main Services:', error.message, '\n', error.stack ?? '');
          if (config.isDebug) {
            this.showFaultDialog(error);
          }
        })

      withLongTask('ApmThreadServices', startMonitorServices, filterConfig(config))
        .catch((error: Error) => {
          this.log.error('Error in APMCore Thread Services:', error.message, '\n', error.stack ?? '');
          if (config.isDebug) {
            this.showFaultDialog(error, 100);
          }
        })

    } catch (error) {
      this.log.error('Error initializing APMCore:', error.message, error.stack);
    }
  }

  private showFaultDialog(reason: Error, ms: number = 0) {
    withLock<void>("ApmStarter:faultDialog", () => {
      return new Promise(resolve => {
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
    }, { onLockFailed: 'skip' })
  }
}

@Concurrent
function startMonitorServices(config: Partial<APMConfig>) {
  getLogger('ApmStarter').info('Starting APMCore Thread Services');
  APMCore.init(config).startMonitorServices()
}
