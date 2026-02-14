/**
 * BaseInfo (baseInfo) 基础公共字段
 */
export interface BaseInfoData {
  _aid?: string;      // Account ID (user ID), empty if the user is not logged in
  _did?: string;      // Device unique ID (可能在 crash 极端场景缺失
  _av: string;        // Client version
  _ch?: string;       // Client channel
  _at: string;        // Client type (app_type)，如 ohos-mobile
  _sv: string;        // APM SDK version (e.g. 1.0.0)
  _ut: number;        // Upload (build) timestamp, milliseconds
  _appid: string;     // Application ID
  _brand?: string;     // Brand / model (e.g. HUAWEI)
  _biz?: string;      // Business tag / scenario code
  _os?: string;       // Operating system (e.g. ohos-mobile)
  _ov?: string;       // Operating system version (e.g. 4.2)
  _pid?: string;      // Process ID
  _tid?: string;      // Thread ID
  // _duration?: number; // (预留) usage duration (ms)
  _screen?: string;   // Screen resolution (e.g. 414*736)
  _network?: string;  // Network type (4g / 5g / wifi / ...)
  _carrier?: string;  // Carrier / operator
  _bg?: boolean;      // Whether running in background
  _reg?: string;      // System region (CN / US / ...)
  _uuid?: string;     // Unique identifier
  _d_type?: string;   // Device type (tablet / phone / ...)
}

/**
 * BusInfo (busInfo) 主/子类型 + 数据内容
 */
export interface BusInfoDataType {
  _analy_type: number;                 // 主类型代码
  _ct: number;                         // 事件/采集时间戳
  _analy_branch?: number;              // 子类型/分支 (如 OOM / Crash 细分)
  contents: Record<string, string | number | boolean | undefined>[]; // 数据内容 (每个元素一个记录对象)
}
/**
 * 主类型枚举 (与 analy_type 对应)
 * 仅列出当前使用 / 约定值，可按需扩展。
 */
export enum AnalyTypeEnum {
  Crash = 2,
  AppFreeze = 22,
}

/**
 * Crash 分支枚举 (与 _analy_branch 对应)
 */
export enum CrashBranchEnum {
  JsError = 0,
  NativeCrash = 1,
}

/**
 * Code -> 名称 映射 (便于日志/调试/可读落盘)
 */
export const ANALY_TYPE_NAME_MAP: Record<number, string> = {
  2: 'crash',
  22: 'app_freeze',
};

export const CRASH_BRANCH_NAME_MAP: Record<number, string> = {
  0: 'jsError',
  1: 'nativeCrash',
};

/** 获取 analy_type 的可读名称 */
export function getAnalyTypeName(code: number): string {
  return ANALY_TYPE_NAME_MAP[code] ?? `unknown(${code})`;
}

/** 获取 crash 分支(_analy_branch)的可读名称 */
export function getCrashBranchName(code: number): string {
  return CRASH_BRANCH_NAME_MAP[code] ?? `unknown(${code})`;
}

/**
 * ReportPayload 聚合对象
 */
export interface ReportPayload {
  base: BaseInfoData;   // 基础上下文字段
  bus: BusInfoDataType; // 业务主/子类型 + 数据
  extra?: Record<string, string | number | boolean>; // 额外轻量键值 (不纳入 bus.contents)
  attachments?: ReportAttachment[]; // 附件集
  cacheDir: string;     // 对应本地缓存目录 (用于标记/清理)
}

/**
 * 附件元信息
 */
export interface ReportAttachment {
  name: string;
  path: string;
  md5?: string;
  size?: number;
  mime?: string;
}
