import { APMConfig } from "./kapm_config/types";
import { APMCore } from "./kapm_core/APMCore";
import { getLogger, withTiming } from "./utils";
import { withTimingSync } from "./utils/withTiming";

export class ApmStarter {
  private readonly TAG = 'ApmStarter';
  private readonly log = getLogger(this.TAG);

  static start(context: Context, config: Partial<APMConfig>) {
    return withTimingSync<void>("ApmStater:init", () => {
      const apmStarter = new ApmStarter();
      apmStarter.init(context, config)
    });
  }

  private init(context: Context, config: Partial<APMConfig>): void {
    try {
      this.log.info("Initializing APMCore", JSON.stringify({
        isDebug: config.isDebug,
        buildId: config.buildId,
      }));
      APMCore.init(context, config);
      this.log.debug("Initializing APMCore with config: ", JSON.stringify(config))
    } catch (error) {
      this.log.error('Failed to initialize APMCore:', error);
    }
  }
}