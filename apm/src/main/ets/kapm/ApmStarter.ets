import { APMConfig } from "./kapm_config/types";
import { APMCore } from "./kapm_core/APMCore";
import { getLogger, withLongTask } from "./utils";
import { withTimingSync } from "./utils/withTiming";

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
        .onError(error => {
          if (config.isDebug) this.showFaultDialog(error)
        })
      withLongTask('ApmThreadServices', startMonitorServices, filterConfig(config))
        .catch((error: Error) => this.showFaultDialog(error))

    } catch (error) {
      this.log.error('Error initializing APMCore:', error.message, error.stack);
    }
  }

  private faultDialogShown = false

  private showFaultDialog(reason: Error): void {
    if (this.faultDialogShown) {
      return;
    }
    this.faultDialogShown = true;

    const message = `Error name: ${reason.name}\nError message: ${reason.message}\nStacktrace:\n${reason.stack}`;
    setTimeout(() => {
      AlertDialog.show({
        title: "Crash Happened...",
        message: message,
        autoCancel: true,
        alignment: DialogAlignment.Bottom,
        offset: { dx: 0, dy: -20 },
        gridCount: 4,
        cancel: () => this.faultDialogShown = false,
      })
    })
  }
}


function filterConfig(config: Partial<APMConfig>) {
  config.logBackend = undefined;
  return config
}

@Concurrent
function startMonitorServices(config: Partial<APMConfig>) {
  getLogger('ApmStarter').info('Starting APMCore Thread Services');
  APMCore.init(config).startMonitorServices()
}
