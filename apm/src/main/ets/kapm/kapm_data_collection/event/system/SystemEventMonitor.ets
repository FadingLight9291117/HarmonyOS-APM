import { ApmEventMonitor } from "../ApmEventMonitor";
import { hiAppEvent } from "@kit.PerformanceAnalysisKit";

export abstract class SystemEventMonitor implements ApmEventMonitor {
  eventName(): string {
    return this.watcherName()
  }

  /**
   * 自定义观察者名称，系统会使用名称来标识不同的观察者
   *
   * @returns
   */
  abstract watcherName(): string


  /**
   * 订阅系统事件
   *
   * @returns
   */
  abstract eventFilters(): string[]


  /**
   * 收到事件回调
   *
   * @param domain
   * @param appEventGroups
   */
  abstract onReceive(domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>)

  addWatcher(): void {
    hiAppEvent.addWatcher({
      name: this.eventName(),
      appEventFilters: [
        {
          domain: hiAppEvent.domain.OS,
          names: this.eventFilters()
        }
      ],
      //  可以自行实现订阅实时回调函数，以便对订阅获取到的事件数据进行自定义处理
      onReceive: (domain: string, appEventGroups: Array<hiAppEvent.AppEventGroup>) => {
        this.onReceive(domain, appEventGroups)
      }
    })
  }
}