import { SystemEventMonitor } from "../SystemEventMonitor";
import { hiAppEvent } from "@kit.PerformanceAnalysisKit";
import { EventChannel, EventType } from "../../EventChannel";
import { getLogger } from "../../../../utils/log/Logger";

/**
 * 监控崩溃
 */
export class EventsMonitor extends SystemEventMonitor {
  private log = getLogger('CrashMonitor')

  watcherName(): string {
    return "wps_app_events_watcher"
  }

  eventFilters(): string[] {
    // 订阅崩溃事件
    // 一次性监听多种系统事件
    return [hiAppEvent.event.APP_CRASH, hiAppEvent.event.APP_FREEZE]
  }

  onReceive(domain: string, appEventGroups: hiAppEvent.AppEventGroup[]) {
    for (const eventGroup of appEventGroups) {
      for (const eventInfo of eventGroup.appEventInfos) {
        this.log.info(`Received crash event: time=${eventInfo.params["time"]}, type=${eventInfo.params["crash_type"]}`)
        const eventName: string = eventInfo.name ?? "UNKNOWN";
        this.dispatchEvent(eventName, eventInfo);

      }
    }
  }

  private dispatchEvent(eventName: string, eventInfo: hiAppEvent.AppEventInfo) {
    switch (eventName) {
      case hiAppEvent.event.APP_CRASH:
        this.handleCrashEvent(eventInfo);
        break;
      case hiAppEvent.event.APP_FREEZE:
        this.handleFreezeEvent(eventInfo);
        break;
      default:
        this.log.warn(`Unhandled system event: ${eventName}`);
    }
  }

  private handleCrashEvent(eventInfo: hiAppEvent.AppEventInfo) {
    const crashType: string = (eventInfo.params["crash_type"] ?? "").toUpperCase();
    const eventType: EventType =
      crashType === 'JSERROR' ? EventType.JS_ERROR : EventType.NATIVE_CRASH;

    this.log.info(`Dispatching crash event -> type=${crashType}, time=${eventInfo.params["time"]}`);
    EventChannel.getInstance().publish(eventType, eventInfo);
  }

  private handleFreezeEvent(eventInfo: hiAppEvent.AppEventInfo) {
    this.log.info(`Dispatching freeze event -> time=${eventInfo.params["time"]}`);
    EventChannel.getInstance().publish(EventType.APP_FREEZE, eventInfo);
  }
}