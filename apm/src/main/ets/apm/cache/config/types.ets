/**
 * 清理优先级枚举
 * 数字越大优先级越高（越晚被清理）
 */
export enum CleanupPriority {
  /** 低优先级 - 优先被清理 */
  LOW = 1,
  /** 普通优先级 - 次要保留 */
  NORMAL = 2,
  /** 高优先级 - 重点保留 */
  HIGH = 3,
  /** 关键优先级 - 最后清理 */
  CRITICAL = 4
}

export interface DataTypeEntry {
  /** 逻辑数据类型名称（事件类型或业务分类） */
  name: string;
  /** 清理/调度优先级（数字越大优先级越高） */
  priority?: number;
  /** 物理分组目录名：<cacheDir>/<group>/<eventDir> */
  group: string;
}

export type CacheDataTypes = Array<string | DataTypeEntry>;

export interface CacheConfig {
  /** 调试模式（禁用定时器等） */
  isDebug?: boolean;
  /** 缓存根目录（末尾可带/） */
  cacheDir: string;
  /** 事件保留天数 */
  retentionDays: number;
  /** 每个 dataType 目录最大事件数 */
  maxEventsPerDir: number;
  /** 总占用空间上限（字节） */
  maxTotalSize: number;
  /** 数据类型列表 */
  dataTypes: CacheDataTypes;
  /** 清理时为防止临界值频繁触发的回收超调因子 */
  spaceCleanupOvershootFactor?: number;
  /** 若启用，则在常规过期清理后额外清理所有已上传(带 .uploaded 标记)的事件目录 */
  enableUploadedEventsCleanup?: boolean;
  /** 事件目录布局模式已固定为 hierarchical，保留字段已移除 */
}
