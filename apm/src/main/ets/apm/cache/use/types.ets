import { CachedFileMeta } from "../save/types";
import { FileInfo } from "../types/FileInfo";

export interface BuildOptions {
  skipUploaded?: boolean;  // 是否跳过已上传的事件（存在 .uploaded 标记文件）
}

// .meta 文件内容类型（JSON 格式的元数据）
export type MetaFileContent = CachedFileMeta

// 旧: ByTypeStats 包含 size/invalid；新需求：仅需要文件数（仍保留 invalid 方便上层判断质量）
export interface ByTypeStats { events: number; files: number; invalid: number; size: number }

// 新的统计结构：
// - totalEvents: 事件总数（按目录/base）
// - totalFiles: 文件总数（仍保留，便于容量观测）
// - byType: 每种 dataType 的文件数与 invalid 数
export interface StatsResult { totalEvents: number; totalFiles: number; totalSize: number; byType: Record<string, ByTypeStats> }

export interface NextOptions { includeSize?: boolean }
export interface PeekOptions { limit: number; includeSize?: boolean }
export interface AnalyTypes { analyType: number; analyBranch?: number }
export interface ExtendedFileInfo extends FileInfo {
  size?: number;
  name?: string;
  analyType: number;       // 主类型 analy_type (必填)
  analyBranch?: number;    // 分支类型 analy_branch (可选)
}

/**
 * 完整的事件信息（包含元数据和文件列表）
 * 用于 next() 方法返回，保持"以事件为原子"的设计原则
 */
export interface EventWithFiles {
  // 事件级元数据
  base: string;                    // 事件目录名，如 jsError_1695868800123
  dataType: string;                // 事件类型（jsError, nativeCrash, appFreeze 等）
  createTime: number;              // 事件创建时间（毫秒时间戳）
  priority: number;                // 优先级（数字越大优先级越高）

  // 分析类型（事件级）
  analyType: number;               // 主分析类型（Crash, AppFreeze 等）
  analyBranch?: number;            // 分析分支类型（JsError, NativeCrash 等，可选）

  // 结构与状态
  hasUploaded?: boolean;           // 是否已上传（存在 .uploaded 标记）

  // Meta 数据（已解析）
  metaFilePath?: string;      	 // .meta 文件的路径（可能不存在或解析失败）

  // hiappevent info filepath
  eventInfoPath?: string;  		 // .json 文件的路径（可能不存在或解析失败）

  // 附件列表（仅路径）
  attachments: string[];           // 该事件的所有附件文件路径（json/log 等，不包含 .meta）

  // 统计信息
  attachmentCount: number;         // 附件数量（不包含 .meta）
  totalSize?: number;              // 总大小（包含 .meta 和所有附件，仅当 includeSize=true 时有值）
}

export type NextResult = EventWithFiles | null;  // next() 返回单个事件或 null
export type PeekResult = ExtendedFileInfo[];     // peek() 仍返回文件数组（用于快速预览）