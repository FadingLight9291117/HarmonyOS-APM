import { getLogger, safeFileOperation } from '../../utils';
import { BuildOptions, ExtendedFileInfo, NextResult, PeekOptions, PeekResult, StatsResult, ByTypeStats, MetaFileContent,
  NextOptions,
  AnalyTypes} from './types';
import { AnalyTypeEnum, CrashBranchEnum } from '../../types/uploadTypes';
import { defaultCacheConfig } from '../config/CacheConfig';
import { getFileSystem, FileSystem } from '../../platform/FileSystem';
import { CacheConfig, DataTypeEntry } from '../config/types';
import { scanEvents } from '../scan/scanEvents';
import { EventInfo, EventScanOptions } from '../scan/types';

export class CacheUseManager {
  private readonly log = getLogger('CacheUseManager');
  private readonly fs: FileSystem;
  private readonly config: CacheConfig;
  private readonly cacheDir: string;
  private readonly dataTypes: DataTypeEntry[];
  private priorityMap: Record<string, number> = {};
  // 事件级缓存：直接使用 scanEvents 返回的事件数组（已按 priority desc, createTime asc 排序）
  private events: EventInfo[] = [];
  private built: boolean = false;
  private cursor: number = 0;

  constructor(cfg?: CacheConfig, fsImpl: FileSystem = getFileSystem()) {
    this.config = cfg ?? defaultCacheConfig;
    this.fs = fsImpl;
    this.cacheDir = this.config.cacheDir;
    this.dataTypes = (this.config.dataTypes || []).map(dt => typeof dt === 'string' ? { name: dt, priority: 3, group: dt } : dt);
    for (const dt of this.dataTypes) this.priorityMap[dt.name] = dt.priority ?? 3;
  }

  /**
   * 构建内部索引（只执行一次，后续调用会被跳过）
   * 逻辑：
   * 1. 调用 scanEvents 扫描事件目录，产出事件及其文件集合
   * 2. 保持事件级别的原子性（不再扁平化为文件列表）
   * 3. scanEvents 已按 priority 降序、createTime 升序排序（高优先+早产生的优先消费）
   *
   * 性能注意：
   * - 不会读取文件内容或计算 size（size 按需延迟计算）
   * - 只在第一次需要数据时执行，可通过 refresh 重新触发
   *
   * @param options.skipUploaded 是否跳过已上传的事件（存在 .uploaded 标记文件）
   */
  async build(options: BuildOptions = {}): Promise<void> {
    if (this.built) return;
    const skipUploaded: boolean = !!options.skipUploaded;

    // 统一扫描事件（hierarchical only）
    // 如果 skipUploaded=false，则 includeUploadedMarker=true（保留已上传事件并标记）
    // 如果 skipUploaded=true，则不传 includeUploadedMarker（默认跳过已上传事件）
    const scanOpts: EventScanOptions = {
      includeUploadedMarker: !skipUploaded  // skipUploaded=false 时，包含已上传事件并标记
    };
    const scanRes = await scanEvents(this.cacheDir, this.dataTypes, scanOpts, this.fs);
    // 保持事件级结构，scanEvents 已完成排序
    this.events = scanRes.events;
    this.cursor = 0;
    this.built = true;
    const totalFiles = this.events.reduce((sum, ev) => sum + ev.files.length, 0);
    this.log.info('build:done(hierarchical)', JSON.stringify({ events: this.events.length, files: totalFiles, skipUploaded }));
  }

  /**
   * 重置内部状态（清空事件列表和游标）。
   * 下次访问时会重新构建索引。
   */
  reset(): void {
    this.events = [];
    this.built = false;
    this.cursor = 0;
  }

  /**
   * 重置游标（用于重新遍历事件）。
   */
  resetCursor(): void {
    this.cursor = 0;
  }

  /**
   * 迭代返回下一个事件（以事件为原子）。
   * 每次调用返回一个完整事件，包含事件元数据、metadata 和所有附件。返回 null 表示已耗尽。
   *
   * 大小策略：
   * - 当 includeSize=false：totalSize = undefined（不计算大小）
   * - 当 includeSize=true：对事件内每个文件延迟执行 stat 获取 size，并计算 totalSize
   *
   * @param opts.includeSize 是否计算并返回文件大小
   * @returns 完整的事件信息（包含元数据、metadata 和附件列表）；若无更多事件则为 null
   */
  async next(opts: NextOptions = {}): Promise<NextResult> {
    const includeSize: boolean = !!opts.includeSize;
    if (!this.built) await this.build();

    // 迭代事件，meta 无效时 metadata 为 undefined，但不跳过事件
    if (this.cursor < this.events.length) {
      const event: EventInfo = this.events[this.cursor++];

      const attachments: string[] = [];
      let metaFilePath: string | undefined = undefined;
      let eventInfoPath: string | undefined = undefined;
      let totalSize: number = 0;

      // 获取事件级的 analyType 和 analyBranch
      const analyResult = this.resolveAnalyTypes(event.dataType);
      const analyType: number = analyResult.analyType;
      const analyBranch: number | undefined = analyResult.analyBranch;

      // 处理事件的所有文件，分离 .meta, .json 和附件
      for (const f of event.files) {
        const fileName: string = this.fs.basename(f.path);

        if (includeSize) {
          const s = await safeFileOperation(() => this.getFileSize(f.path));
          const fileSize: number = typeof s === 'number' ? s : 0;
          totalSize += fileSize;
        }

        // 判断是否为 .meta 文件
        if (fileName.endsWith('.meta')) {
          // 只记录路径，不解析内容
          metaFilePath = f.path;
        } else if (fileName.endsWith('.json')) {
          // 记录 eventInfo 文件路径
          eventInfoPath = f.path;
          // JSON 文件也加入附件列表
          attachments.push(f.path);
        } else {
          // 其他文件作为附件（只存路径）
          attachments.push(f.path);
        }
      }

      // 返回完整的事件结构
      return {
        // 事件元数据
        base: event.base,
        dataType: event.dataType,
        createTime: event.createTime,
        priority: event.priority,
        analyType,
        analyBranch,

        // 状态
        hasUploaded: event.hasUploaded,

        // 文件路径
        metaFilePath,
        eventInfoPath,

        // 附件列表
        attachments,

        // 统计信息
        attachmentCount: attachments.length,
        totalSize: includeSize ? totalSize : undefined,
      };
    }

    return null;
  }

  /**
   * 预览前 N 个事件的文件（不改变迭代 cursor）。
   * 用于观测当前缓存内的排序及事件分布。
   *
   * 大小策略与 next 类似：
   * - includeSize=false：返回 size=-1
   * - includeSize=true：按需获取 stat
   *
   * @param limitOrOpts 数字（limit）或对象 { limit, includeSize }
   * @param includeSizeLegacy 兼容旧签名：当第一个参数是数字且第二个布尔为 true，表示需要 size
   */
  async peek(limitOrOpts: number | PeekOptions, includeSizeLegacy: boolean = false): Promise<PeekResult> {
    if (!this.built) await this.build();
    let limit: number;
    let includeSize: boolean;

    if (typeof limitOrOpts === 'number') {
      limit = limitOrOpts;
      includeSize = includeSizeLegacy;
    } else {
      limit = limitOrOpts.limit;
      includeSize = !!limitOrOpts.includeSize;
    }

    this.log.info('peek:start', JSON.stringify({ limit, includeSize }));

    const result: PeekResult = [];
    const eventsToPreview: EventInfo[] = this.events.slice(0, limit);

    for (const event of eventsToPreview) {
      for (const f of event.files) {
        const analyResult = this.resolveAnalyTypes(f.dataType);
        const analyType: number = analyResult.analyType;
        const analyBranch: number | undefined = analyResult.analyBranch;
        const fileName: string = this.fs.basename(f.path);

        let fileSize: number = -1;
        if (includeSize) {
          const s = await safeFileOperation(() => this.getFileSize(f.path));
          fileSize = typeof s === 'number' ? s : 0;
        }

        result.push({
          path: f.path,
          dataType: f.dataType,
          priority: f.priority,
          createTime: event.createTime,
          size: fileSize,
          name: fileName,
          analyType,
          analyBranch,
        });
      }
    }

    this.log.info('peek:done', JSON.stringify({ returned: result.length, includeSize }));
    return result;
  }

  /**
   * 新统计：聚焦事件数量 & 按类型的文件数量。
   * - totalEvents: this.events.length
   * - totalFiles: 所有文件数量（与旧 totalFiles 含义一致）
   * - byType: { events, files, invalid, size }
   * invalid 计算：存在任何文件 valid === false 计入 invalid 文件数
   */
  async stats(calcSize: boolean = false): Promise<StatsResult> {
    if (!this.built) await this.build();

    const byType: Record<string, ByTypeStats> = {};
    for (const dt of this.dataTypes) {
      byType[dt.name] = { files: 0, events: 0, invalid: 0, size: -1 };
    }

    let totalFiles: number = 0;
    let totalSize: number = calcSize ? 0 : -1;

    // 遍历事件进行统计
    for (const ev of this.events) {
      byType[ev.dataType].events++;

      for (const f of ev.files) {
        totalFiles++;
        byType[f.dataType].files++;

        if (calcSize) {
          let fileSize: number | undefined = f.size;
          if (!fileSize || fileSize < 0) {
            const s = await safeFileOperation(() => this.getFileSize(f.path));
            fileSize = typeof s === 'number' ? s : 0;
          }

          if (byType[f.dataType].size < 0) {
            byType[f.dataType].size = 0;
          }
          byType[f.dataType].size += fileSize;
          totalSize += fileSize;
        }
      }
    }

    return {
      totalEvents: this.events.length,
      totalFiles,
      totalSize,
      byType
    };
  }

  /**
   * 重新扫描并构建索引，然后返回新的事件/文件统计。
   */
  async refresh(calcSize: boolean = false): Promise<StatsResult> {
    this.built = false; // 标记为未构建，强制重新扫描
    await this.build();
    return this.stats(calcSize);
  }

  /**
   * 获取文件大小（失败返回 null）
   * @param p 文件路径
   * @returns 文件大小（字节），失败返回 null
   */
  private async getFileSize(p: string): Promise<number | null> {
    try {
      const st = await this.fs.stat(p);
      return st.size;
    } catch {
      return null;
    }
  }

  /**
   * 根据 dataType 推导 analyType / analyBranch
   * 规则：
   * - jsError -> Crash / JsError
   * - nativeCrash -> Crash / NativeCrash
   * - appFreeze -> AppFreeze / (无分支)
   * - 其他：返回 analyType=0 (未知)，不设置分支
   */
  private resolveAnalyTypes(dataType: string): AnalyTypes {
    switch (dataType) {
      case 'jsError':
        return { analyType: AnalyTypeEnum.Crash, analyBranch: CrashBranchEnum.JsError };
      case 'nativeCrash':
        return { analyType: AnalyTypeEnum.Crash, analyBranch: CrashBranchEnum.NativeCrash };
      case 'appFreeze':
        return { analyType: AnalyTypeEnum.AppFreeze };
      default:
        return { analyType: 0 };
    }
  }
}
