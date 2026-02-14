import { CacheConfig, DataTypeEntry } from './types';
import { defaultCacheConfig } from './CacheConfig';

// Helper function to merge cache config (ArkTS doesn't support object spread)
function mergeCacheConfig(base: CacheConfig, overrides: Partial<CacheConfig>): CacheConfig {
  return {
    cacheDir: overrides.cacheDir ?? base.cacheDir,
    retentionDays: overrides.retentionDays ?? base.retentionDays,
    maxEventsPerDir: overrides.maxEventsPerDir ?? base.maxEventsPerDir,
    maxTotalSize: overrides.maxTotalSize ?? base.maxTotalSize,
    dataTypes: overrides.dataTypes ?? base.dataTypes,
    spaceCleanupOvershootFactor: overrides.spaceCleanupOvershootFactor ?? base.spaceCleanupOvershootFactor,
    enableUploadedEventsCleanup: overrides.enableUploadedEventsCleanup ?? base.enableUploadedEventsCleanup,
    isDebug: overrides.isDebug ?? base.isDebug
  };
}

// Helper function to clone cache config (ArkTS doesn't support object spread)
function cloneCacheConfig(config: CacheConfig): CacheConfig {
  return {
    cacheDir: config.cacheDir,
    retentionDays: config.retentionDays,
    maxEventsPerDir: config.maxEventsPerDir,
    maxTotalSize: config.maxTotalSize,
    dataTypes: config.dataTypes,
    spaceCleanupOvershootFactor: config.spaceCleanupOvershootFactor,
    enableUploadedEventsCleanup: config.enableUploadedEventsCleanup,
    isDebug: config.isDebug
  };
}

export class CacheConfigManager {
  private config: CacheConfig;

  constructor(overrides: Partial<CacheConfig> = {}) {
    this.config = mergeCacheConfig(defaultCacheConfig, overrides);
    this.validateConfig(this.config);
  }

  getConfig(): CacheConfig {
    return cloneCacheConfig(this.config);
  }

  /**
   * 验证配置以确保必填字段存在且有效
   * @throws Error 如果配置无效
   */
  private validateConfig(config: CacheConfig): void {
    // 验证缓存目录
    if (!config.cacheDir || config.cacheDir.trim().length === 0) {
      throw new Error('CacheConfig.cacheDir must be a non-empty string');
    }

    // 验证保留天数
    if (config.retentionDays !== undefined && config.retentionDays <= 0) {
      throw new Error('CacheConfig.retentionDays must be positive');
    }

    // 验证每个目录的最大事件数
    if (config.maxEventsPerDir !== undefined && config.maxEventsPerDir <= 0) {
      throw new Error('CacheConfig.maxEventsPerDir must be positive');
    }

    // 验证总空间上限
    if (config.maxTotalSize !== undefined && config.maxTotalSize <= 0) {
      throw new Error('CacheConfig.maxTotalSize must be positive');
    }

    // 验证超调因子
    if (config.spaceCleanupOvershootFactor !== undefined) {
      if (config.spaceCleanupOvershootFactor < 1) {
        throw new Error('CacheConfig.spaceCleanupOvershootFactor must be >= 1.0');
      }
    }

    // 验证数据类型列表
    if (!config.dataTypes || config.dataTypes.length === 0) {
      throw new Error('CacheConfig.dataTypes must be a non-empty array');
    }

    // 验证每个数据类型条目
    config.dataTypes.forEach((dt, index) => {
      if (typeof dt === 'string') {
        if (dt.trim().length === 0) {
          throw new Error(`CacheConfig.dataTypes[${index}] must be a non-empty string`);
        }
      } else {
        const entry = dt as DataTypeEntry;
        if (!entry.name || entry.name.trim().length === 0) {
          throw new Error(`CacheConfig.dataTypes[${index}].name must be a non-empty string`);
        }
        if (!entry.group || entry.group.trim().length === 0) {
          throw new Error(`CacheConfig.dataTypes[${index}].group must be a non-empty string`);
        }
        if (entry.priority !== undefined && entry.priority < 0) {
          throw new Error(`CacheConfig.dataTypes[${index}].priority must be non-negative`);
        }
      }
    });
  }
}

