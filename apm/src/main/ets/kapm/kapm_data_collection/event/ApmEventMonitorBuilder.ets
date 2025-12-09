import { ArrayList } from "@kit.ArkTS"
import { ApmEventMonitor } from "./ApmEventMonitor"

export class ApmEventMonitorBuilder {
  private eventMonitors = new ArrayList<ApmEventMonitor>()

  public append(eventMonitor: ApmEventMonitor) {
    this.eventMonitors.add(eventMonitor)
    return this
  }

  public build() {
    this.eventMonitors.forEach((eventMonitor) => {
      // 开始监听
      eventMonitor.addWatcher()
    })
  }
}