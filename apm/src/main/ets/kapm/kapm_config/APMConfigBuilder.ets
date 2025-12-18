import { APMConfig } from './types';
import { getFileSystem } from '../platform/FileSystem';
import { APMConfigManager } from './APMConfigManager';
import { getDefaultApmConfig } from './defaultConfig';
import { IKLogAdapter, KLogAdapter, LogBackend } from '../utils/log/Logger';


/**
 * APM 配置构建器
 * 使用 Builder 模式构建配置
 */
export class APMConfigBuilder {
  private config: Partial<APMConfig> = {};
  private context: Context;
  private valid: boolean = true

  private constructor(context: Context) {
    this.context = context;
    this.configCacheDir();
  }

  private configCacheDir() {
    this.config.cacheDir =
      getFileSystem().join(this.context.getApplicationContext().filesDir, getDefaultApmConfig().cacheDir);
  }

  static create(context: Context, valid: boolean = true): APMConfigBuilder {
    const instance = new APMConfigBuilder(context);
    instance.valid = valid
    return instance;
  }

  setCommitRevision(commitRevision: string): APMConfigBuilder {
    this.config.commitRevision = commitRevision;
    return this;
  }

  setBranchName(branchName: string): APMConfigBuilder {
    this.config.branchName = branchName;
    return this;
  }

  /**
   * 设置应用类型（必填，需要从外部传入）
   * @param appType 应用类型/客户端类型，对应 _at
   */
  setAppType(appType: string): APMConfigBuilder {
    this.config.appType = appType;
    return this;
  }

  /**
   * 设置应用渠道（必填，需要从外部传入）
   * @param channel 应用渠道，对应 _ch
   */
  setChannel(channel: string): APMConfigBuilder {
    this.config.channel = channel;
    return this;
  }

  /**
   * 设置应用版本（必填，需要从外部传入）
   * @param appVersion 应用版本，对应 _av
   */
  setAppVersion(appVersion: string): APMConfigBuilder {
    this.config.appVersion = appVersion;
    return this;
  }

  /**
   * 设置内核版本（可选，需要从外部传入）
   * @param kernelVersion 内核版本
   */
  setKernelVersion(kernelVersion: string): APMConfigBuilder {
    this.config.kernelVersion = kernelVersion;
    return this;
  }

  /**
   * 设置应用包ID（可选，需要从外部传入）
   * @param bundleName 应用包ID
   */
  setBundleName(bundleName: string): APMConfigBuilder {
    this.config.bundleName = bundleName;
    return this;
  }

  /**
   * 设置调试模式（可选，需要从外部传入）
   */
  setDebug(isDebug: boolean): APMConfigBuilder {
    this.config.isDebug = isDebug;
    return this;
  }

  /**
   * 设置加密密钥（可选，需要从外部传入）
   * @param keyHex 密钥十六进制字符串
   * @param iv 初始化向量
   */
  setKeys(keyHex: string, iv: string): APMConfigBuilder {
    this.config.keys = [keyHex, iv];
    return this;
  }

  /**
   * 设置日志后端（可选，用于自定义日志输出）
   * @param logBackend 实现 LogBackend 接口的日志实现
   */
  setLogBackend(logBackend: IKLogAdapter): APMConfigBuilder {
    this.config.logBackend = new KLogAdapter(logBackend)
    return this;
  }

  setDeviceId(deviceId: string): APMConfigBuilder {
    this.config.deviceId = deviceId;
    return this;
  }

  setBuildId(buildId: string): APMConfigBuilder {
    this.config.buildId = buildId;
    return this;
  }

  setProductName(name: string): APMConfigBuilder {
    this.config.productName = name;
    return this;
  }

  // 在这里添加额外的信息
  setExtraInfo(info: Record<string, string | number | boolean>) {
    this.config.extras = info;
    return this;
  }

  /**
   * 验证必填的外部参数
   * @throws Error 如果必填参数缺失或无效
   */
  private validateRequiredParams(): void {
    if (!this.config.appType || !this.config.appType.trim()) {
      throw new Error('APMConfigBuilder: appType is required, call setAppType()');
    }
    if (!this.config.channel || !this.config.channel.trim()) {
      throw new Error('APMConfigBuilder: channel is required, call setChannel()');
    }
    if (!this.config.appVersion || !this.config.appVersion.trim()) {
      throw new Error('APMConfigBuilder: appVersion is required, call setAppVersion()');
    }
  }

  private _setUserId?: () => string | undefined;

  setUserIdFunc(func: () => string): APMConfigBuilder {
    this._setUserId = func;
    return this;
  }

  /**
   * 构建最终配置
   * @returns 部分配置对象（将被 APMConfigManager 合并默认值和验证）
   * @throws Error 如果必填参数缺失或无效
   */
  build(): Partial<APMConfig> {
    if (this.valid) {
      this.validateRequiredParams();
    }
    this.setDynamicConfig()
    return this.config;
  }

  private setDynamicConfig() {
    if (this._setUserId) {
      APMConfigManager.getInstance().setGetUserIdFunc(this._setUserId)
    }
  }

}
