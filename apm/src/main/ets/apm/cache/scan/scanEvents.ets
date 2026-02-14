import { CacheValidation } from '../clean/validation';
import { safeFileOperation } from '../../utils';
import { getFileSystem, FileSystem } from '../../platform/FileSystem';
import { EventScanOptions, EventScanResult, EventInfo, EventFileInfo } from './types';
import { DataTypeEntry } from '../config/types';

/**
 * 上传标记文件名常量
 */
const UPLOAD_MARKER_FILE = '.uploaded';

/**
 * 事件扫描器类
 * 负责扫描缓存目录中的事件，支持层级布局和各种过滤选项
 *
 * 层级布局: <cacheDir>/<group-or-dt>/<eventDir>/<files>
 * 事件目录模式: <dataType>_<timestamp>
 */
export class EventScanner {
  private readonly fs: FileSystem;
  private readonly cacheDir: string;
  private readonly dataTypes: DataTypeEntry[];
  private readonly options: EventScanOptions;
  private readonly priorityMap: Record<string, number> = {};

  private events: EventInfo[] = [];
  private errors: ScanError[] = [];
  private scanStartTime: number = 0;

  constructor(
    cacheDir: string,
    dataTypes: Array<string | DataTypeEntry>,
    options: EventScanOptions = {},
    fs: FileSystem = getFileSystem()
  ) {
    this.cacheDir = cacheDir;
    this.fs = fs;
    this.options = options;

    // 规范化数据类型配置并构建优先级映射表
    this.dataTypes = dataTypes.map(d => {
      const dt: DataTypeEntry = typeof d === 'string' ? { name: d, priority: 3, group: d } : d;
      this.priorityMap[dt.name] = dt.priority ?? 3;
      return dt;
    });
  }

  /**
   * 执行扫描并返回结果
   */
  async scan(): Promise<EventScanResult> {
    this.scanStartTime = Date.now();
    this.events = [];
    this.errors = [];

    // 按组对数据类型进行分组
    const groupMap = this.buildGroupMap();

    // 扫描所有组
    await this.scanAllGroups(groupMap, this.events, this.errors);

    const scanMs = Date.now() - this.scanStartTime;

    // 收集文件统计信息（如果需要）
    let statMs: number | undefined;
    let totalBytes = 0;

    if (this.options.includeStat) {
      const stats = await this.collectStats(this.events, this.errors);
      totalBytes = stats.totalBytes;
      statMs = stats.statMs;
    }

    // 排序事件：按优先级降序，相同优先级按时间戳升序
    const sortedEvents = this.events.sort(
      (a, b) => (b.priority - a.priority) || (a.createTime - b.createTime)
    );

    return {
      events: sortedEvents,
      totals: {
        files: this.events.reduce((sum, ev) => sum + ev.files.length, 0),
        events: this.events.length,
        bytes: this.options.includeStat ? totalBytes : undefined
      },
      errors: this.errors,
      timings: { scanMs, statMs }
    };
  }

  /**
   * 检测上传标记文件是否存在
   */
  private async detectUploadMarker(eventDirPath: string): Promise<boolean> {
    return await safeFileOperation(() =>
    this.fs.exists(this.fs.join(eventDirPath, UPLOAD_MARKER_FILE))
    ) === true;
  }

  /**
   * 处理事件目录中的文件列表
   */
  private processEventFiles(
    fileList: string[],
    eventDirPath: string,
    entry: string,
    matched: DataTypeEntry,
    entryTimestamp: number
  ): EventFileInfo[] {
    return fileList
      .filter(fname => fname !== UPLOAD_MARKER_FILE)
      .map<EventFileInfo>(fname => ({
        path: this.fs.join(eventDirPath, fname),
        dataType: matched.name,
        base: entry,
        createTime: CacheValidation.extractTimestampFromFilename(fname) || entryTimestamp,
        priority: this.priorityMap[matched.name] ?? 3
      }));
  }

  /**
   * 并行收集文件统计信息
   */
  private async collectStats(
    events: EventInfo[],
    errors: ScanError[]
  ): Promise<StatsResult> {
    const s0 = Date.now();
    let totalBytes = 0;

    // 收集所有文件的 stat 操作
    const allFiles = events.flatMap(ev => ev.files);

    await Promise.all(allFiles.map(async (f) => {
      const st = await safeFileOperation(() => this.fs.stat(f.path));
      if (!st) {
        errors.push({ path: f.path, code: 'STAT_ERROR' });
        return;
      }
      f.size = st.size;
      totalBytes += st.size;
    }));

    return { totalBytes, statMs: Date.now() - s0 };
  }

  /**
   * 构建组映射表
   */
  private buildGroupMap(): Map<string, GroupBucket> {
    const groupMap = new Map<string, GroupBucket>();

    for (const dt of this.dataTypes) {
      const root = this.fs.join(this.cacheDir, dt.group || dt.name);
      const bucket = groupMap.get(root);

      if (bucket) {
        bucket.dts.push(dt);
      } else {
        groupMap.set(root, { root, dts: [dt] });
      }
    }

    return groupMap;
  }

  /**
   * 扫描所有组目录
   */
  private async scanAllGroups(
    groupMap: Map<string, GroupBucket>,
    events: EventInfo[],
    errors: ScanError[]
  ): Promise<void> {
    for (const groupBucket of groupMap.values()) {
      const root = groupBucket.root;
      const dts = groupBucket.dts;

      const dirList = await safeFileOperation(() => this.fs.readdir(root));
      if (!Array.isArray(dirList)) continue;

      for (const entry of dirList as string[]) {
        // 跳过非事件目录
        if (!CacheValidation.isValidEventDir(entry)) continue;

        // 根据目录名模式确定 dataType：<dataType>_<timestamp>
        // 使用最长匹配以避免前缀重叠（例如 'js' vs 'jsError'）
        const matched = dts
          .filter(d => entry.startsWith(d.name + '_'))
          .sort((a, b) => b.name.length - a.name.length)[0];

        if (!matched) continue;

        const eventDirPath = this.fs.join(root, entry);

        // 检测上传标记
        const hasUploadMarker = await this.detectUploadMarker(eventDirPath);

        // 如果存在上传标记且不需要包含已上传事件，则跳过
        if (hasUploadMarker && !this.options.includeUploadedMarker) {
          continue;
        }

        // 读取事件目录中的文件列表
        const fileList = await safeFileOperation(() => this.fs.readdir(eventDirPath));
        if (!Array.isArray(fileList) || fileList.length === 0) continue;

        // 提取事件时间戳并处理事件文件
        const createTime = CacheValidation.extractTimestampFromFilename(entry) || 0;
        const files = this.processEventFiles(fileList as string[], eventDirPath, entry, matched, createTime);

        // 添加事件信息
        events.push({
          dataType: matched.name,
          base: entry,
          createTime,
          priority: this.priorityMap[matched.name] ?? 3,
          files,
          hasUploaded: hasUploadMarker
        });
      }
    }
  }
}

/**
 * 组桶接口 - 用于按组织数据类型
 */
interface GroupBucket {
  root: string;
  dts: DataTypeEntry[];
}

/**
 * 扫描错误信息接口
 */
interface ScanError {
  path: string;
  code: string;
}

/**
 * 统计结果接口
 */
interface StatsResult {
  totalBytes: number;
  statMs: number;
}

// 导出兼容的函数接口，内部使用 EventScanner 类
export async function scanEvents(
  cacheDir: string,
  dataTypes: Array<string | DataTypeEntry>,
  options: EventScanOptions = {},
  fs: FileSystem = getFileSystem()
): Promise<EventScanResult> {
  const scanner = new EventScanner(cacheDir, dataTypes, options, fs);
  return scanner.scan();
}
