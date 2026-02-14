/**
 * 缓存保存相关类型定义
 * 根据华为 hiappevent 文档规范定义
 */

import { UploadInfo } from "../../config/types";

/**
 * 异常信息对象
 */
export interface ExceptionInfo {
  name?: string;
  message?: string;
  stack?: string;
  additionalFields?: Record<string, string | number | boolean>;
}

/**
 * 线程信息对象
 */
export interface ThreadInfo {
  name?: string;
  stack?: string[];
  tid?: number;
  additionalFields?: Record<string, string | number | boolean>;
}

/**
 * 内存信息对象
 */
export interface MemoryInfo {
  total?: number;
  used?: number;
  free?: number;
  additionalFields?: Record<string, string | number | boolean>;
}

/**
 * 华为 hiappevent 事件信息参数
 * 根据文档中的 .json 文件信息规范定义
 */
export interface EventInfoParams {
  /** 事件触发时间（毫秒） */
  time: number;
  /** 应用是否在前台（true 表示前台） */
  foreground: boolean;
  /** 应用版本 */
  bundle_version: string;
  /** 应用名称 */
  bundle_name: string;
  /** 进程 ID */
  pid: number;
  /** 应用用户 ID */
  uid: number;
  /** 故障特征码，用于标识相同故障 */
  uuid: string;
  /** 异常简要信息（完整信息见 external_log） */
  exception?: ExceptionInfo;
  /** hiLog 日志片段，最多显示 100 行 */
  hilog?: string[];
  /** 全量线程调用栈 */
  threads?: ThreadInfo[];
  /** 故障日志文件应用沙箱路径。开发者可通过路径读取故障日志文件内容。 */
  external_log?: string[]
  /** 生成的与已存在的故障日志文件的大小总和是否超过5M上限。true表示超过上限，日志写入失败；false表示未超过上限。 */
  log_over_limit?: boolean;


  // 崩溃事件特有字段
  /** 崩溃类型：`NativeCrash`（native）或 `JsError`（JS） */
  crash_type?: string;

  // 冻屏事件特有字段
  /** 进程名称 */
  process_name?: string;
  /** 主线程未处理消息 */
  event_handler?: string[];
  /** THREAD_BLOCK_6S 事件中 3s 时任务栈的任务数量 */
  event_handler_size_3s?: string;
  /** THREAD_BLOCK_6S 事件中 6s 时任务栈的任务数量 */
  event_handler_size_6s?: string;
  /** Binder 调用信息 */
  peer_binder?: string[];
  /** 内存信息 */
  memory?: MemoryInfo;
}

/**
 * 缓存文件元数据
 */
export interface CachedFileMeta {
  uploadInfo: UploadInfo;
  extra: Record<string, string | number | boolean>;
}