export interface CleanupResult {
  /** 删除的事件数量 */
  deletedEvents: number;
  /** 保留的事件数量 */
  retainedEvents: number;
  /** 释放空间（字节） */
  freedSpace: number;
  /** 错误计数 */
  errorCount: number;
  startTime?: number;
  endTime?: number;
  duration?: number;
  phases?: Record<string, CleanupResult>;
}

export interface SpaceStatus {
  totalSize: number;
  needCleanup: boolean;
  overSize: number
}

/**
 * 批量删除事件的结果
 */
export interface BatchDeleteResult {
  /** 成功删除的事件数量 */
  deleted: number;
  /** 删除失败的事件列表 */
  failed: string[];
  /** 释放的空间总量（字节） */
  freedSpace: number;
}
