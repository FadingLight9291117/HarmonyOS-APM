import { APMConfig } from './types';

/**
 * APM配置的默认值
 * 包含所有配置字段的默认设置
 */
const DEFAULT_CONFIG: APMConfig = {
  // SDK 核心配置
  sdkVersion: '1.1.0',
  appId: '<YOUR_APP_ID>',
  encrypt_ver: 'ohos-mobile-v1',
  isDebug: true,
  keys: [], // 密钥

  // 网络配置
  baseURL: '<YOUR_BASE_URL>',
  maxRetryCount: 1,
  retryInterval: 1000,

  // 缓存配置
  fileRetentionDays: 7,
  cacheDir: './apm_cache',
  useExistingZip: false,
  enableEncryptTransfer: true,

  // 应用信息（平铺字段）
  appVersion: '1.0.0',
  appType: 'wps-ohos-mobile',
  channel: '1.0.0'
};


/**
 * APM配置的测试用例
 */
const TEST_CONFIG: APMConfig = {
  // SDK 核心配置
  sdkVersion: '1.1.0-test',
  appId: '<YOUR_APP_ID>',
  encrypt_ver: 'ohos-mobile-v1',
  keys: [],
  isDebug: true,
  disableAutoCleanup: true, // 测试环境下禁用自动清理

  // 网络配置
  baseURL: 'http://localhost:3000',

  // 缓存配置
  cacheDir: 'apm_cache',
  useExistingZip: false,
  enableEncryptTransfer: true,

  // 应用信息（平铺字段）
  appVersion: '1.0.0',
  appType: 'wps-ohos-mobile',
  channel: '1.0.0'
};

export const getDefaultApmConfig = () => DEFAULT_CONFIG;