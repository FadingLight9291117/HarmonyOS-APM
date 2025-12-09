import { hiAppEvent } from "@kit.PerformanceAnalysisKit";
import { getLogger } from "../../utils";

const logger = getLogger('EventChannel');

/**
 * Event Channel
 *
 * 功能是接受每个Monitor.onReceive产生的event数据，
 * 并在AppMonitorService中调用接受，然后进行后续消费数据的操作
 *
 * 采用观察者模式，支持多个监听器订阅事件
 */
export class EventChannel {
  private static instance: EventChannel | null = null;
  private listeners: Map<string, EventListener[]> = new Map();

  private constructor() {
  }

  /**
   * 获取单例实例
   */
  static getInstance(): EventChannel {
    return EventChannel.instance ??= new EventChannel();
  }

  /**
   * 订阅事件
   * @param eventType 事件类型（如 'APP_CRASH', 'APP_FREEZE'）
   * @param listener 事件监听器
   */
  subscribe(eventType: EventType, listener: EventListener): void {
    if (!this.listeners.has(eventType)) {
      this.listeners.set(eventType, []);
    }

    const listeners = this.listeners.get(eventType);
    if (listeners && !listeners.includes(listener)) {
      listeners.push(listener);
      logger.info(`Subscribed to event: ${eventType}, total listeners: ${listeners.length}`);
    }
  }

  /**
   * 订阅多个事件类型
   * @param eventTypes 事件类型数组
   * @param listener 事件监听器
   */
  subscribeAll(eventTypes: EventType[], listener: EventListener): void {
    if (!eventTypes || eventTypes.length === 0) {
      logger.warn('subscribeAll called with empty event types array');
      return;
    }

    let subscribed = 0;
    for (const eventType of eventTypes) {
      if (!this.listeners.has(eventType)) {
        this.listeners.set(eventType, []);
      }

      const listeners = this.listeners.get(eventType);
      if (listeners && !listeners.includes(listener)) {
        listeners.push(listener);
        subscribed++;
      }
    }

    logger.info(`Subscribed to ${subscribed} event types: [${eventTypes.join(', ')}]`);
  }

  /**
   * 取消订阅事件
   * @param eventType 事件类型
   * @param listener 事件监听器
   */
  unsubscribe(eventType: EventType, listener: EventListener): void {
    const listeners = this.listeners.get(eventType);
    if (listeners) {
      const index = listeners.indexOf(listener);
      if (index > -1) {
        listeners.splice(index, 1);
        logger.info(`Unsubscribed from event: ${eventType}, remaining listeners: ${listeners.length}`);
      }

      if (listeners.length === 0) {
        this.listeners.delete(eventType);
      }
    }
  }

  /**
   * 发布原始 AppEventInfo 数据
   * @param eventType 事件类型
   * @param domain 事件域
   * @param eventInfo 原始事件信息
   */
  publish(eventType: EventType, eventInfo: hiAppEvent.AppEventInfo): void {
    const listeners = this.listeners.get(eventType);

    if (!listeners || listeners.length === 0) {
      logger.warn(`No listeners for raw event: ${eventType}`);
      return;
    }

    logger.info(`Publishing raw event: ${eventType} to ${listeners.length} listener(s)`);

    for (const listener of listeners) {
      listener(eventType, eventInfo)
        .catch((error: Error) => {
          logger.error(`Error in raw event listener for ${eventType}:`, error.message);
        });
    }
  }

  /**
   * 检查是否有监听器订阅了指定事件
   * @param eventType 事件类型
   */
  hasListeners(eventType: EventType): boolean {
    const listeners = this.listeners.get(eventType);
    return listeners !== undefined && listeners.length > 0;
  }

  /**
   * 获取指定事件的监听器数量
   * @param eventType 事件类型
   */
  getListenerCount(eventType: EventType): number {
    const listeners = this.listeners.get(eventType);
    return listeners ? listeners.length : 0;
  }

  /**
   * 清空所有监听器
   */
  clear(): void {
    const totalListeners = Array.from(this.listeners.values())
      .reduce((sum, listeners) => sum + listeners.length, 0);

    this.listeners.clear();
    logger.debug(`Cleared all event listeners, removed ${totalListeners} listener(s)`);
  }

  /**
   * 获取所有已注册的事件类型
   */
  getRegisteredEventTypes(): string[] {
    return Array.from(this.listeners.keys());
  }
}

/**
 * 事件监听器
 * 处理原始事件数据
 * @param eventInfo 原始事件信息
 */
export type EventListener =  (eventType: EventType, eventInfo: hiAppEvent.AppEventInfo) => Promise<void>;

export enum EventType {
  JS_ERROR = 'jsError',
  NATIVE_CRASH = 'nativeCrash',
  APP_FREEZE = 'appFreeze',
}