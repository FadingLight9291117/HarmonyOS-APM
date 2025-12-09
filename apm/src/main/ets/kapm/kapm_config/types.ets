import { LogBackend } from "../utils/log/Logger";

/**
 * 上传信息接口
 * 描述上报过程本身的信息
 */
export interface UploadInfo {
  userId?: string;       // 对应 _aid
  timestamp: number;    // 对应 _ut (必填)
  businessTag?: string;  // 对应 _biz
  processId?: string;    // 对应 _pid
  threadId?: string;     // 对应 _tid
  isBackground?: boolean; // 对应 _bg
  sessionId?: string;    // 对应 _uuid
  network?: string;       // 对应 _network
  carrier?: string;       // 对应 _carrier
  region?: string;        // 对应 _reg
}

/**
 * APM配置接口
 * 包含所有APM相关的配置信息
 */
export interface APMConfig {
  // ==================== SDK核心配置 ====================
  /** SDK版本，对应 _sv (必填) */
  sdkVersion: string;
  /** 应用ID，对应 _appid (必填) */
  appId: string;
  /** 加密版本 */
  encrypt_ver: string;
  /** 服务端基础URL */
  baseURL: string;
  /** 是否开启调试模式（启用详细日志和测试友好行为） */
  isDebug?: boolean;
  /** 加密密钥数组（十六进制格式） */
  keys: string[];
  /** 是否禁用自动清理 */
  disableAutoCleanup?: boolean;

  // ==================== 网络配置 ====================
  /** 即时重试次数（用于 token 获取和上传） */
  maxRetryCount?: number;
  /** 重试间隔时间（毫秒） */
  retryInterval?: number;

  // ==================== 缓存配置 ====================
  /** 缓存文件保留天数 */
  fileRetentionDays?: number;
  /** 缓存文件基础目录路径 */
  cacheDir: string;
  /** 是否使用已存在的 ZIP 文件 */
  useExistingZip?: boolean;

  // ==================== 传输配置 ====================
  /** 是否开启加密传输 */
  enableEncryptTransfer?: boolean;

  // ==================== 日志配置 ====================
  /** 日志后端（可选，用于自定义日志输出） */
  logBackend?: LogBackend;

  // ==================== 系统信息字段 ====================
  /** 设备品牌，对应 _brand */
  brand?: string;
  /** 设备ID，对应 _did */
  deviceId?: string;
  /** 操作系统，对应 _os */
  os?: string;
  /** 操作系统版本，对应 _ov */
  osVersion?: string;
  /** 屏幕分辨率，对应 _screen */
  screen?: string;
  /** 设备类型，对应 _d_type */
  deviceType?: string;

  // ==================== 应用信息字段 ====================
  /** 应用版本，对应 _av (必填) */
  appVersion: string;
  /** 应用类型/客户端类型，对应 _at (必填) */
  appType: string;
  /** 应用渠道，对应 _ch (必填) */
  channel: string;
  /** 内核版本 */
  kernelVersion?: string;
  /** 应用包名 */
  bundleName?: string;
  /** git 分支名称 */
  branchName?: string;
  /** git 提交版本 */
  commitRevision?: string;
  /** buildId */
  buildId?: string;
  /** product name */
  productName?: string;

  /** 自定义扩展字段 */
  extras?: Record<string, string | number | boolean>;
}

export interface DynamicInfo {
  userId: string | undefined
}
