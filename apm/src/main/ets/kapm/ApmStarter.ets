import { APMConfig } from "./kapm_config/types";
import { APMCore } from "./kapm_core/APMCore";
import { getLogger, stopLongTask, withLongTask } from "./utils";
import { withTimingSync } from "./utils/withTiming";
import { errorManager } from "@kit.AbilityKit";

export class ApmStarter {
  private readonly TAG = 'ApmStarter';
  private readonly log = getLogger(this.TAG);

  static start(context: Context, config: Partial<APMConfig>) {
    return withTimingSync<void>("ApmStater:init", () => {
      const apmStarter = new ApmStarter();
      apmStarter.init(config)
    });
  }

  private init(config: Partial<APMConfig>): void {
    this.log.info("Initializing APMCore", JSON.stringify({ isDebug: config.isDebug, buildId: config.buildId }));

    try {
      APMCore.init(config)
        .startCacheServices()
        .startNetConService()

      withLongTask('ApmThreadServices', startMonitorServices, config)
        .catch((err: Error) => {
          this.log.error('Error ApmThreadServices:', err.message);

          setTimeout(() => {
            AlertDialog.show({
              message: "Failed to start APM thread services: " + err.message,
            })
          })
        });

      this.registeredJsErrorObserver(config);

    } catch (error) {
      this.log.error('Error initializing APMCore:', error.message, error.stack);
    }
  }

  static stop(): void {
    stopLongTask('startServices')
  }

  private registeredJsErrorObserver(config: Partial<APMConfig>) {
    try {
      const observer: errorManager.ErrorObserver = {
        onUnhandledException: (errorMsg) => {
          this.log.error(this.TAG, 'onUnhandledException, errorMsg: ' + errorMsg);
          if (config.isDebug) {
            this.showFaultDialog(errorMsg);
          }
        }
      }
      errorManager.on("error", observer);
    } catch (error) {
    }
  }

  private faultDialogShown = false

  private showFaultDialog(fault: string) {
    if (this.faultDialogShown) {
      return;
    }

    this.faultDialogShown = true;
    setTimeout(() => {
      AlertDialog.show({
        title: "Crash Happened...",
        message: fault,
        autoCancel: true,
        alignment: DialogAlignment.Bottom,
        offset: { dx: 0, dy: -20 },
        gridCount: 4,
        cancel: () => this.faultDialogShown = false,
      })
    })
  }
}

@Concurrent
function startMonitorServices(config: Partial<APMConfig>) {
  getLogger('ApmStarter').info('Starting APMCore Thread Services');
  APMCore.init(config).startMonitorServices()
}
