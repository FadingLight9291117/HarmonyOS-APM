import { UploadResp } from './networkTypes';
import { BaseInfoData, BusInfoDataType, ReportAttachment } from './uploadTypes';

export interface ReportResult extends UploadResp {
  eventId: string; // 事件唯一标识符
}

/**
 * ZIP 打包结果信息
 * 用于 reportZip 方法返回打包后的 ZIP 文件元信息
 */
export interface ReportZipResult {
  fileName: string; // 生成的 ZIP 文件名
  md5: string;      // ZIP 文件的 MD5 哈希值（十六进制字符串）
  size: number;     // ZIP 文件的字节大小
  cachePath: string;// ZIP 文件在缓存目录中的路径
}

/**
 * Parameter types for report payload builders
 */

/**
 * 构建崩溃记录所需的参数
 * 用于 buildCrashRecord 函数构建单个崩溃事件记录
 */
export interface BuildCrashRecordParams {
  crash_type: string | number;  // 崩溃类型（如 "TypeError", "SIGSEGV" 等）
  crash_id?: string;            // 崩溃唯一标识符
  crash_name?: string;          // 崩溃名称（如异常类名、信号符号等）
  crash_reason?: string;        // 崩溃原因或错误消息

  debug: boolean;               // 是否为调试包（商店正式包为 false）
  kernel_version: string;       // 内核版本信息
  fingerprint: string;          // 根据故障信息生成的故障特征码，用于标识特征相同的崩溃故障。
}

/**
 * 构建应用冻屏记录所需的参数
 * 用于 buildAppFreezeRecord 函数构建单个冻屏事件记录
 */
export interface BuildAppFreezeRecordParams {
  freeze_id?: string;        // 冻屏事件 ID
  freeze_duration?: number;  // 卡死持续时间 (ms)
  freeze_name?: string;      // 冻屏名称
  freeze_reason?: string;    // 冻屏原因

  debug: boolean;            // 是否调试包（商店正式包 false）
  kernel_version: string;    // 内核版本
  fingerprint: string;       // 根据故障信息生成的故障特征码，用于标识特征相同的崩溃故障。
}

/**
 * 构建报告载荷所需的参数
 * 用于 buildReportPayload 函数构建完整的报告数据结构
 */
export interface BuildReportPayloadArgs {
  base: BaseInfoData;                    // 基础信息（设备、应用、运行环境等公共信息）
  bus: BusInfoDataType;                  // 业务信息（主类型、分支、事件内容数组）
  extra?: Record<string, string | number | boolean>;           // 额外扩展字段（轻量键值对，不进入统计明细）
  attachments?: ReportAttachment[];      // 附件列表（日志、压缩包、堆栈等文件）
  cacheDir: string;                      // 本地缓存事件目录（用于标记上传完成和清理）
}