import { UploadInfo, APMConfig } from './types';


export namespace TypeHelper {
  // Helper function to merge UploadInfo (ArkTS doesn't support object spread)
  export function mergeUploadInfo(base?: UploadInfo, overrides?: Partial<UploadInfo>): UploadInfo | undefined {
    if (overrides === undefined || overrides === null) {
      return base;
    }
    if (base === undefined || base === null) {
      return overrides as UploadInfo;
    }
    const result: UploadInfo = {
      timestamp: 0
    };
    result.userId = overrides.userId ?? base.userId;
    result.timestamp = overrides.timestamp ?? base.timestamp;
    result.businessTag = overrides.businessTag ?? base.businessTag;
    result.processId = overrides.processId ?? base.processId;
    result.threadId = overrides.threadId ?? base.threadId;
    result.isBackground = overrides.isBackground ?? base.isBackground;
    result.sessionId = overrides.sessionId ?? base.sessionId;
    result.network = overrides.network ?? base.network;
    result.carrier = overrides.carrier ?? base.carrier;
    result.region = overrides.region ?? base.region;
    return result;
  }

  /**
   * 合并 APM 配置
   * @param base 基础配置
   * @param overrides 覆盖配置（部分字段）
   * @returns 合并后的完整配置
   */
  export function mergeAPMConfig(base: APMConfig, overrides: Partial<APMConfig>): APMConfig {
    return {
      // SDK核心配置
      sdkVersion: overrides.sdkVersion ?? base.sdkVersion,
      appId: overrides.appId ?? base.appId,
      encrypt_ver: overrides.encrypt_ver ?? base.encrypt_ver,
      baseURL: overrides.baseURL ?? base.baseURL,
      isDebug: overrides.isDebug ?? base.isDebug,
      keys: overrides.keys ?? base.keys,
      disableAutoCleanup: overrides.disableAutoCleanup ?? base.disableAutoCleanup,

      // 网络配置
      maxRetryCount: overrides.maxRetryCount ?? base.maxRetryCount,
      retryInterval: overrides.retryInterval ?? base.retryInterval,

      // 缓存配置
      fileRetentionDays: overrides.fileRetentionDays ?? base.fileRetentionDays,
      cacheDir: overrides.cacheDir ?? base.cacheDir,
      useExistingZip: overrides.useExistingZip ?? base.useExistingZip,

      // 传输配置
      enableEncryptTransfer: overrides.enableEncryptTransfer ?? base.enableEncryptTransfer,

      // 日志配置
      logBackend: overrides.logBackend ?? base.logBackend,

      // 系统信息字段
      brand: overrides.brand ?? base.brand,
      deviceId: overrides.deviceId ?? base.deviceId,
      os: overrides.os ?? base.os,
      osVersion: overrides.osVersion ?? base.osVersion,
      screen: overrides.screen ?? base.screen,
      deviceType: overrides.deviceType ?? base.deviceType,

      // 应用信息字段
      appVersion: overrides.appVersion ?? base.appVersion,
      appType: overrides.appType ?? base.appType,
      channel: overrides.channel ?? base.channel,
      kernelVersion: overrides.kernelVersion ?? base.kernelVersion,
      bundleName: overrides.bundleName ?? base.bundleName,
      commitRevision: overrides.commitRevision ?? base.commitRevision,
      branchName: overrides.branchName ?? base.branchName,
      buildId: overrides.buildId ?? base.buildId,
      productName: overrides.productName ?? base.productName,

      // extras info
      extras: overrides.extras ?? base.extras,
    };
  }
}
