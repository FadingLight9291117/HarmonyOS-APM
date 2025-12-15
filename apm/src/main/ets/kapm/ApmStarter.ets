import { APMConfig } from "./kapm_config/types";
import { APMCore } from "./kapm_core/APMCore";
import { getLogger, stopLongTask, withLongTask } from "./utils";
import { withTimingSync } from "./utils/withTiming";

export class ApmStarter {
  private readonly TAG = 'ApmStarter';
  private readonly log = getLogger(this.TAG);

  static start(config: Partial<APMConfig>) {
    return withTimingSync<void>("ApmStater:init", () => {
      const apmStarter = new ApmStarter();
      apmStarter.init(config)
    });
  }

  private init(config: Partial<APMConfig>): void {
    this.log.info("Initializing APMCore", JSON.stringify({ isDebug: config.isDebug, buildId: config.buildId }));

    withLongTask('startServices', startServices, config)
      .catch((err: Error) => {
        this.log.error('Error startServices:', err.message);
      });
  }

  static stop(): void {
    stopLongTask('startServices')
  }
}

@Concurrent
function startServices(config: Partial<APMConfig>) {
  APMCore.init(config).startServices()
}
