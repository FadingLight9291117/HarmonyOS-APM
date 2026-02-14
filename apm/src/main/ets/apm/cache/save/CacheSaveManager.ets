import { FileSystem } from '../../platform/FileSystem';
import { UploadInfo } from '../../config/types';
import { getLogger } from '../../utils';
import { CacheConfig } from '../config/types';
import { EventInfoParams, CachedFileMeta } from './types';

/**
 * 缓存保存选项
 */
export interface CacheSaveOptions {
  /** 数据类型名称，用于确定缓存目录分组 */
  dataType: string;
  /** 上传信息 */
  uploadInfo: UploadInfo;
  /** 事件信息 */
  eventInfo: EventInfoParams;
  /** 事件时间戳，默认为当前时间 */
  eventTimestamp: number;
  /** 额外数据，可选 */
  extra?: Record<string, string | number | boolean>;
}

export class CacheSaveManager {
  private readonly TAG = 'CacheSaveManager';
  private readonly log = getLogger(this.TAG);
  private fs: FileSystem;
  private cacheConfig: CacheConfig;

  constructor(cacheConfig: CacheConfig, fsImpl: FileSystem) {
    this.fs = fsImpl;
    this.cacheConfig = cacheConfig;
  }

  /**
   * 保存报告载荷到缓存
   */
  async saveToCache(options: CacheSaveOptions): Promise<SaveCacheResult> {
    try {
      const dataType = options.dataType;
      const uploadInfo = options.uploadInfo;
      const eventInfo = options.eventInfo;
      const eventTimestamp = options.eventTimestamp;
      const extra = options.extra;

      // 1. 构建缓存目录路径
      const cacheDir = this.buildCacheDirectory(dataType, eventTimestamp);

      // 2. 确保缓存目录存在
      await this.ensureCacheDirectory(cacheDir);

      // 3. 生成文件名和完整路径
      const jsonFileName = this.generateJsonFileName(dataType, eventTimestamp);
      const metaFileName = this.generateMetaFileName(dataType, eventTimestamp);
      const jsonPath = this.fs.join(cacheDir, jsonFileName);
      const metaPath = this.fs.join(cacheDir, metaFileName);

      // 4. 保存 JSON 文件（事件信息）
      await this.saveEventInfoToFile(eventInfo, jsonPath);

      // 5. 保存日志文件（从 eventInfo.external_log 提取）
      const logPaths = await this.saveLogFiles(dataType, eventInfo, cacheDir);

      // 6. 保存元数据文件（包含 payload 信息）
      await this.saveMetaToFile(uploadInfo, extra || {}, metaPath);

      this.log.debug('Report payload saved:', JSON.stringify({
        dataType: options.dataType,
        jsonPath: jsonPath,
        metaPath: metaPath,
        logPaths: logPaths,
      }));

      const attachments = [jsonPath, ...logPaths];

      return {
        dataType: options.dataType,
        cacheDir: cacheDir,
        metaPath: metaPath,
        eventTimestamp: eventTimestamp,
        attachments: attachments,
      };

    } catch (error) {
      this.log.error('Failed to save report payload to cache:', JSON.stringify({
        dataType: options.dataType,
        error: error.message || error
      }));
      throw new Error(`Faild to save report payload to cache: [${options.dataType}]: ${error.message || error}`);
    }
  }

  /**
   * 构建缓存目录路径
   * 根据文档规范：<cacheDir>/<group>/<eventDir>
   * 其中 eventDir = <dataType>_<timestamp>
   */
  private buildCacheDirectory(dataType: string, eventTimestamp: number): string {
    const timestamp = eventTimestamp;

    // 查找 dataType 对应的 group
    const group = this.findGroupForDataType(dataType);

    // 格式: <cacheDir>/<group>/<dataType>_<timestamp>/
    return this.fs.join(this.cacheConfig.cacheDir, group, `${dataType}_${timestamp}`);
  }

  /**
   * 查找 dataType 对应的 group
   */
  private findGroupForDataType(dataType: string): string {
    for (const dataTypeEntry of this.cacheConfig.dataTypes) {
      if (typeof dataTypeEntry === 'string') {
        if (dataTypeEntry === dataType) {
          return dataType; // 默认使用 dataType 作为 group
        }
      } else {
        if (dataTypeEntry.name === dataType) {
          return dataTypeEntry.group || dataType; // 使用配置的 group 或默认 dataType
        }
      }
    }
    return dataType; // 默认使用 dataType 作为 group
  }

  /**
   * 确保缓存目录存在
   */
  private async ensureCacheDirectory(cacheDir: string): Promise<void> {
    try {
      await this.fs.ensureDir(cacheDir);
    } catch (error) {
      this.log.error('Failed to create cache directory:', JSON.stringify({ cacheDir, error }));
      throw new Error(`Failed to create cache directory: ${cacheDir}`);
    }
  }

  /**
   * 生成元数据文件名
   * 根据文档规范：<dataType>_<timestamp>.meta
   */
  private generateMetaFileName(dataType: string, eventTimestamp: number): string {
    const timestamp = eventTimestamp;
    return `${dataType}_${timestamp}.meta`;
  }

  /**
   * 生成 JSON 文件名
   * 根据文档规范：<dataType>_<timestamp>.json
   */
  private generateJsonFileName(dataType: string, eventTimestamp: number): string {
    const timestamp = eventTimestamp;
    return `${dataType}_${timestamp}.json`;
  }

  /**
   * 生成日志文件名
   * 根据文档规范：<dataType>_<timestamp>.log 或 <dataType>_<timestamp>_<number>.log
   */
  private generateLogFileName(dataType: string, eventTimestamp: number, index?: number): string {
    const timestamp = eventTimestamp;
    if (index !== undefined && index > 0) {
      return `${dataType}_${timestamp}_${index}.log`;
    }
    return `${dataType}_${timestamp}.log`;
  }

  /**
   * 保存元数据到文件（包含完整 payload 信息）
   */
  private async saveMetaToFile(uploadInfo: UploadInfo, extra: Record<string, string | number | boolean>, filePath: string): Promise<void> {
    try {
      const meta: CachedFileMeta = {
        uploadInfo: uploadInfo,
        extra: extra,
      };
      const content = JSON.stringify(meta, null, 2);
      await this.fs.writeFile(filePath, content);
    } catch (error) {
      this.log.error('Failed to write meta to file:', JSON.stringify({ filePath, error }));
      throw new Error(`Failed to write meta to file: ${filePath}`);
    }
  }

  /**
   * 保存事件信息到 JSON 文件
   */
  private async saveEventInfoToFile(eventInfo: EventInfoParams, filePath: string): Promise<void> {
    try {
      const content = JSON.stringify(eventInfo, null, 2);
      await this.fs.writeFile(filePath, content);
    } catch (error) {
      this.log.error('Failed to write event info to file:', JSON.stringify({ filePath, error }));
      throw new Error(`Failed to write event info to file: ${filePath}`);
    }
  }

  /**
   * 保存日志文件（从 external_log 字段提取）
   */
  private async saveLogFiles(dataType: string, eventInfo: EventInfoParams, cacheDir: string): Promise<string[]> {
    const logPaths: string[] = [];
    const eventTimestamp = eventInfo.time;

    if (!eventInfo.external_log || eventInfo.external_log.length === 0) {
      return logPaths;
    }

    try {
      // 从 external_log 路径读取日志内容并保存
      for (let i = 0; i < eventInfo.external_log.length; i++) {
        const externalLogPath = eventInfo.external_log[i];
        const logFileName = this.generateLogFileName(dataType, eventTimestamp, i);
        const logPath = this.fs.join(cacheDir, logFileName);

        try {
          // 读取外部日志文件内容
          const content = await this.fs.readFile(externalLogPath);
          // const content =await fileIo.readText(externalLogPath);
          await this.fs.writeFile(logPath, content);
          logPaths.push(logPath);
        } catch (readError) {
          this.log.warn('Failed to read external log file:', JSON.stringify({
            externalLogPath,
            error: readError
          }));
          // 如果读取失败，创建一个占位文件
          await this.fs.writeFile(logPath, `Failed to read external log: ${externalLogPath}`);
          logPaths.push(logPath);
        }
      }

      this.log.info('Log files saved:', JSON.stringify({
        dataType: dataType,
        logCount: logPaths.length,
        logPaths: logPaths
      }));

    } catch (error) {
      this.log.error('Failed to save log files:', JSON.stringify({ error }));
      throw new Error(`Failed to save log files: ${error}`);
    }

    return logPaths;
  }
}

export interface SaveCacheResult {
  dataType: string;
  cacheDir: string;
  metaPath: string;
  eventTimestamp: number;
  attachments: string[];
}