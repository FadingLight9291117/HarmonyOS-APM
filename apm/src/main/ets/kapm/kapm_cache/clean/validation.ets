export namespace CacheValidation {
  // Allow optional numeric suffix after the timestamp (e.g. _1) and optional extension
  const BASE_PATTERN = /^[A-Za-z0-9]+_(\d{10,13})(?:_\d+)?(?:\.[A-Za-z0-9]+)?$/;
  /** Hierarchical layout specific patterns */
  const EVENT_DIR_PATTERN = /^[A-Za-z0-9]+_(\d{10,13})$/; // directory name
  const JSON_FILE_PATTERN = /^[A-Za-z0-9]+_(\d{10,13})\.json$/;
  const META_FILE_PATTERN = /^[A-Za-z0-9]+_(\d{10,13})\.meta$/;
  const LOG_FILE_PATTERN = /^[A-Za-z0-9]+_(\d{10,13})(?:_\d+)?\.log$/; // multiple logs allowed

  /** Generic timestamp extractor shared by both layouts */
  function normalizeTimestamp(raw: string): number {
    if (raw.length === 10) {
      const secs = parseInt(raw, 10);
      return Number.isFinite(secs) ? secs * 1000 : 0;
    }
    if (raw.length === 13) {
      const ms = parseInt(raw, 10);
      return Number.isFinite(ms) ? ms : 0;
    }
    const num = parseInt(raw, 10);
    if (!Number.isFinite(num) || num <= 0) {
      return 0;
    }
    return num < 1e11 ? num * 1000 : num;
  }

  /**
   * Extract timestamp from filename or directory name and normalize to milliseconds.
   */
  export function extractTimestampFromFilename(filename: string): number {
    const m = filename.match(/^[A-Za-z0-9]+_(\d{10,13})/);
    if (!m) {
      return 0;
    }
    return normalizeTimestamp(m[1]);
  }

  // ---------------- Flat layout legacy helpers ----------------
  export function isValidFileName(filename: string): boolean {
    return BASE_PATTERN.test(filename);
  }

  export function isStructuredJson(filename: string): boolean {
    return /\.json$/i.test(filename) && isValidFileName(filename);
  }

  export interface ExtractFileNameMetaResult {
    valid: boolean;
    structuredJson: boolean;
    createTime: number;
  }

  export function extractFileNameMeta(filename: string): ExtractFileNameMetaResult {
    const valid = isValidFileName(filename);
    const structuredJson = valid && /\.json$/i.test(filename);
    return { valid, structuredJson, createTime: extractTimestampFromFilename(filename) || 0 };
  }

  // ---------------- Hierarchical layout helpers ----------------
  export function isValidEventDir(dirName: string): boolean {
    return EVENT_DIR_PATTERN.test(dirName);
  }

  export interface ExtractEventDirMetaResult {
    valid: boolean;
    createTime: number;
  }

  export function extractEventDirMeta(dirName: string): ExtractEventDirMetaResult {
    const valid = isValidEventDir(dirName);
    return { valid, createTime: valid ? extractTimestampFromFilename(dirName) : 0 };
  }

  export type EventFileKind = 'json' | 'meta' | 'log' | 'attachment' | 'unknown';

  export interface ClassifiedEventFileMeta {
    kind: EventFileKind;
    base: string;
    timestamp: number;
    valid: boolean
  }
}
