import { APMConfig, DynamicInfo } from './types';
import { TypeHelper } from './helper';
import { getDefaultApmConfig } from './defaultConfig';
import { setBackend } from '../utils';
import { deviceInfo } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import BuildProfile from 'BuildProfile';


export class APMConfigManager {
  private static instance: APMConfigManager | null = null;
  private config: APMConfig;

  private constructor() {
    this.config = getDefaultApmConfig();
    this.configSysInfo();
    this.configFixedValues();
    this.setDefaultConfig();
  }


  private configFixedValues() {
    this.config.bundleName = BuildProfile.BUNDLE_NAME
  }

  // 配置默认值
  private setDefaultConfig() {
    this.config.maxRetryCount ??= 1;
    this.config.retryInterval ??= 3000;
    this.config.fileRetentionDays ??= 7;
  }


  private configSysInfo() {
    this.config.os = deviceInfo.distributionOSName;
    this.config.osVersion = deviceInfo.distributionOSVersion;
    this.config.brand = deviceInfo.brand;
    this.config.deviceType = deviceInfo.deviceType;
    this.config.screen = display.getDefaultDisplaySync().width + 'x' + display.getDefaultDisplaySync().height;
  }


  /**
   * 获取单例实例
   */
  static getInstance(): APMConfigManager {
    if (!APMConfigManager.instance) {
      APMConfigManager.instance = new APMConfigManager();
    }
    return APMConfigManager.instance;
  }

  /**
   * 重置单例（主要用于测试）
   */
  static resetInstance(): void {
    APMConfigManager.instance = null;
  }

  /**
   * 更新配置（运行时修改）
   * @param overrides 配置覆盖
   */
  setConfig(overrides: Partial<APMConfig>): void {
    this.config = TypeHelper.mergeAPMConfig(this.config, overrides);
    this.validateConfig(this.config);


    // 如果提供了自定义 logBackend，应用它
    if (overrides.logBackend) {
      setBackend(overrides.logBackend);
    }
  }

  getConfig(): APMConfig {
    return this.config;
  }

  /**
   * Validate configuration to ensure required fields are present and valid.
   * @throws Error if configuration is invalid
   */
  private validateConfig(config: APMConfig): void {
    // Validate keys format if provided
    if (config.keys && config.keys.length > 0) {
      if (config.keys.length < 2) {
        throw new Error('APMConfig.keys must contain at least 2 elements [keyHex, iv]');
      }

      const keyHex = config.keys[0];
      const iv = config.keys[1];

      // Validate keyHex length (should be at least 32 characters for security)
      if (!keyHex || keyHex.length < 32) {
        throw new Error('APMConfig.keys[0] (keyHex) must be at least 32 characters long');
      }

      // Validate iv is not empty
      if (!iv || iv.length === 0) {
        throw new Error('APMConfig.keys[1] (iv) must be a non-empty string');
      }
    } else {
      throw new Error('APMConfig.keys are required but not provided.');
    }
  }

  // 补充信息
  private _getUserId: (() => string | undefined) | undefined = undefined

  setGetUserIdFunc(func: () => string | undefined): void {
    this._getUserId = func
  }

  getDynamicInfo(): DynamicInfo{
    return {
      userId: this._getUserId?.()
    }
  }
}

