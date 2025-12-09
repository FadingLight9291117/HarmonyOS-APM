import { NetworkService } from './NetworkService';
import { TokenService } from './TokenService';
import { getLogger, withTiming } from '../utils';
import { Crypto } from '../platform/Crypto';
import { getFileSystem } from '../platform/FileSystem';
import { BaseInfoData, BusInfoDataType, ReportPayload, ReportAttachment } from '../types/uploadTypes';
import { EncryptCompressService } from './EncryptCompressService';
import { safeFileOperation } from '../utils/safeOperations';
import { UploadResp } from '../types/networkTypes';
import { buildZipFileName } from '../utils/uploadHelpers';
import { ReportZipResult } from '../types/reportTypes';

// Type for default options
interface DefaultReportOptions {
  readonly extraBytesLimit: number;
  readonly retryInterval: number;
  readonly maxRetryCount: number;
  readonly useExistingZip: boolean;
  readonly shouldEncrypt: boolean,
}

// Constants
const DEFAULT_OPTIONS: DefaultReportOptions = {
  extraBytesLimit: 1024,
  retryInterval: 1000,
  maxRetryCount: 1,
  useExistingZip: false,
  shouldEncrypt: false,
};

const MARKER_FILE_NAME = '.uploaded';
const DATA_FILE_NAME = 'data.json';

/**
 * 上报结果原因常量
 */
enum UPLOAD_REASONS {
  ALREADY_UPLOADED = 'already_uploaded',
  UPLOADED = 'uploaded',
  UPLOAD_FAILED = 'upload_failed',
};

// Type definitions
interface ZipFileInfo {
  path: string;
  fileName: string;
  md5: string;
  size: number;
}

export interface ReportSkippedResult {
  success: boolean;
  skipped: boolean;
  reason: string;
}

export interface ReportServiceOptions {
  networkService: NetworkService;
  tokenService: TokenService;
  ecService: EncryptCompressService;
  /** extra 传输字段字节限制 (默认 1024) */
  extraBytesLimit?: number;
  /** encrypt version 未来扩展：若提供将透传 */
  encryptVersion?: string;
  /** 重试间隔(毫秒), 默认 1000ms */
  retryInterval?: number;
  /** 最大重试次数, 默认 1 次 */
  maxRetryCount?: number;
  /** 是否使用已存在的zip文件 (默认 true) */
  useExistingZip?: boolean;
  /** 是否加密传输 (默认 false) */
  shouldEncrypt?: boolean,
}

// Helper function to merge options (ArkTS doesn't support object spread)
function mergeReportOptions(defaults: DefaultReportOptions, opts: ReportServiceOptions): ReportServiceOptions {
  return {
    networkService: opts.networkService,
    tokenService: opts.tokenService,
    ecService: opts.ecService,
    extraBytesLimit: opts.extraBytesLimit ?? defaults.extraBytesLimit,
    encryptVersion: opts.encryptVersion,
    retryInterval: opts.retryInterval ?? defaults.retryInterval,
    maxRetryCount: opts.maxRetryCount ?? defaults.maxRetryCount,
    useExistingZip: opts.useExistingZip ?? defaults.useExistingZip,
    shouldEncrypt: opts.shouldEncrypt ?? defaults.shouldEncrypt,
  };
}

/*
 * ReportService builds payloads defined in uploadTypes and uploads them either
 * directly as JSON (reportData) or packaged as a zip (reportZip) containing
 * structured JSON parts plus optional attachments.
 */
export class ReportService {
  private network: NetworkService;
  private tokens: TokenService;
  private ecService: EncryptCompressService;
  private fs = getFileSystem();
  private readonly TAG: string = 'ReportService';
  private log = getLogger(this.TAG);
  private opts: ReportServiceOptions;
  private shouldEncrypt: boolean;

  constructor(opts: ReportServiceOptions) {
    this.network = opts.networkService;
    this.tokens = opts.tokenService;
    this.ecService = opts.ecService;
    this.opts = mergeReportOptions(DEFAULT_OPTIONS, opts);
    this.shouldEncrypt = this.opts.shouldEncrypt ?? true
  }

  /**
   * 构建报告载荷
   * @param base 基础信息
   * @param bus 业务信息
   * @param cacheDir 缓存目录
   * @param extra 额外字段
   * @param attachments 附件列表
   * @returns 报告载荷
   */
  buildPayload(
    base: BaseInfoData,
    bus: BusInfoDataType,
    cacheDir: string,
    extra?: Record<string, string | number | boolean>,
    attachments?: ReportAttachment[]
  ): ReportPayload {
    return {
      base,
      bus,
      extra,
      attachments,
      cacheDir
    };
  }


  /** Build a zip buffer with: data.json and attachments. Extra data is merged into busInfo.contents. */
  async buildZip(payload: ReportPayload): Promise<ReportZipResult> {
    const ts = payload.bus._ct;
    const fileName = buildZipFileName(payload.bus, ts);

    // Prepare cache path
    await this.fs.ensureDir(payload.cacheDir);
    const cachePath = this.fs.join(payload.cacheDir, fileName);


    // Add extra to each content's extra field if present
    // Manual clone busInfo (ArkTS doesn't support object spread)
    const busInfo: BusInfoDataType = {
      _analy_type: payload.bus._analy_type,
      _ct: payload.bus._ct,
      _analy_branch: payload.bus._analy_branch,
      contents: payload.bus.contents
    };

    if (payload.extra && Object.keys(payload.extra).length > 0) {
      const extraStr = JSON.stringify(payload.extra);
      busInfo.contents = busInfo.contents.map(content => {
        // Manual clone content (ArkTS doesn't support object spread)
        const newContent: Record<string, string | number | boolean | undefined> = {};
        for (const key of Object.keys(content)) {
          newContent[key] = content[key];
        }
        newContent['extra'] = extraStr;
        return newContent;
      });
    }

    // Create zip builder and add content
    const zipBuilder = this.ecService.createZipBuilder();
    // Add data.json
    const dataJson = JSON.stringify({ baseInfo: payload.base, busInfo });
    zipBuilder.addText(dataJson, DATA_FILE_NAME, this.shouldEncrypt);

    // Add attachments
    payload.attachments?.forEach(att => {
      zipBuilder.addFile(att.path, att.name, this.shouldEncrypt);
    });

    // Build to file
    const result = await zipBuilder.buildToFile(cachePath);

    if (!result) {
      throw new Error('zip build to file failed');
    }


    return {
      fileName: result.filename,
      md5: result.md5,
      size: result.size,
      cachePath: result.zipPath
    };
  }

  async reportZip(payload: ReportPayload): Promise<ReportSkippedResult> {
    return this.executeWithRetry(async () => {
      // Check if already uploaded
      if (await this.shouldSkipUpload(payload.cacheDir, payload.bus._analy_type)) {
        return this.createSkippedResult(payload);
      }

      // record upload timestamp
      const uploadTimestamp = Date.now();
      payload.base._ut = uploadTimestamp;

      // Get or build zip file
      const zipInfo = await withTiming(`${this.TAG}:getOrBuildZipFile`, () => this.getOrBuildZipFile(payload));

      // Prepare and upload
      const result = await withTiming(`${this.TAG}:uploadZipFile`, () => this.uploadZipFile(zipInfo, payload));

      if (!result) {
        this.log.error('reportZip: upload failed, no response', '');
        return { success: false, skipped: false, reason: UPLOAD_REASONS.UPLOAD_FAILED };
      }

      // Write success marker
      await withTiming(`${this.TAG}:writeUploadedMarker`, () => this.writeUploadedMarker(payload.cacheDir, payload.bus._analy_type));
      return { success: true, skipped: false, reason: UPLOAD_REASONS.UPLOADED };

    }, 'reportZip');
  }

  private async shouldSkipUpload(cacheDir: string, analyType: number): Promise<boolean> {
    return await this.hasUploadedMarker(cacheDir, analyType);
  }

  private createSkippedResult(payload: ReportPayload): ReportSkippedResult {
    this.log.info('reportZip: skipping upload, already uploaded marker found', JSON.stringify({
      cacheDir: payload.cacheDir,
      analy_type: payload.bus._analy_type
    }));
    return { success: true, skipped: true, reason: UPLOAD_REASONS.ALREADY_UPLOADED };
  }

  private async getOrBuildZipFile(payload: ReportPayload): Promise<ZipFileInfo> {
    // Try to find existing zip file only if useExistingZip is enabled
    if (this.opts.useExistingZip) {
      const existingZip = await this.findExistingZip(payload.cacheDir, payload.bus._analy_type);
      if (existingZip) {
        this.log.info('reportZip: using existing cached zip', JSON.stringify({ cachePath: existingZip.path, size: existingZip.size }));
        return existingZip;
      }
    } else {
      this.log.debug('reportZip: skipping existing zip search (useExistingZip disabled)');
    }

    // Build new zip file
    this.log.info('reportZip: building new zip file', JSON.stringify({ cacheDir: payload.cacheDir, analyType: payload.bus._analy_type, attachments: payload.attachments?.length }));
    const zip = await this.buildZip(payload);
    this.log.debug('reportZip meta', JSON.stringify({ fileName: zip.fileName, size: zip.size }));

    return {
      path: zip.cachePath,
      fileName: zip.fileName,
      md5: zip.md5,
      size: zip.size
    };
  }


  private async uploadZipFile(
    zipInfo: ZipFileInfo,
    payload: ReportPayload,
  ): Promise<UploadResp | null> {
    const token = await this.tokens.getToken();

    if (!token) {
      this.log.error('uploadZipFile: no valid token available');
      return null;
    }

    return await this.network.uploadFile(zipInfo.path, token, {
      name: zipInfo.fileName,
      type: payload.bus._analy_type,
      type_branch: payload.bus._analy_branch ? payload.bus._analy_branch : undefined,
      encrypt_ver: this.opts.encryptVersion,
    });
  }

  /**
   * Execute operation with automatic retry and error handling.
   */
  private async executeWithRetry<T>(operation: () => Promise<T>, operationName: string): Promise<T> {
    const maxAttempts = (this.opts.maxRetryCount || 0) + 1;
    let lastError: Error;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        this.log.debug(`${operationName}: attempt ${attempt}/${maxAttempts}`);
        const result = await operation();

        this.logRetrySuccess(operationName, attempt);
        return result;
      } catch (error) {
        lastError = error as Error;

        this.handleRetryError(error, operationName);

        if (attempt < maxAttempts) {
          await this.waitBeforeRetry(operationName, attempt, lastError);
        } else {
          this.logFinalFailure(operationName, maxAttempts, lastError);
        }
      }
    }

    throw lastError!;
  }

  private logRetrySuccess(operationName: string, attempt: number): void {
    if (attempt > 1) {
      this.log.info(`${operationName}: succeeded on retry ${attempt - 1}`);
    }
  }

  private handleRetryError(error: Error, operationName: string): void {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.log.warn(`${operationName}: token error detected, invalidating token`, errorMsg);
      this.tokens.invalidateToken();
  }

  private async waitBeforeRetry(
    operationName: string,
    attempt: number,
    error: Error
  ): Promise<void> {
    const delay = this.opts.retryInterval || DEFAULT_OPTIONS.retryInterval;
    this.log.warn(`${operationName}: attempt ${attempt} failed, retrying in ${delay}ms`, error.message);
    await this.delay(delay);
  }

  private logFinalFailure(operationName: string, maxAttempts: number, error: Error): void {
    this.log.error(`${operationName}: all ${maxAttempts} attempts failed`, error.message);
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Find existing zip file in cache directory for the given analy_type.
   */
  private async findExistingZip(cacheDir: string, analyType: number): Promise<ZipFileInfo | null> {
    try {
      const files = await this.fs.readdir(cacheDir);
      const zipFile = this.findMatchingZipFile(files, analyType);

      if (!zipFile) return null;

      return await this.readZipFileInfo(cacheDir, zipFile);
    } catch (error) {
      this.log.debug('findExistingZip: failed to search', JSON.stringify(error));
      return null;
    }
  }

  private findMatchingZipFile(files: string[], analyType: number): string | null {
    const pattern = new RegExp(`^report_.*_${analyType}_\\d+\\.zip$`);
    const zipFiles = files.filter(f => pattern.test(f));

    if (zipFiles.length === 0) return null;

    // Return the most recent file (sort descending)
    return zipFiles.sort().reverse()[0];
  }

  private async readZipFileInfo(
    cacheDir: string,
    fileName: string
  ): Promise<ZipFileInfo> {
    const path = this.fs.join(cacheDir, fileName);
    const buffer = await this.fs.readFileAsBinary(path);
    const md5 = await Crypto.md5(new Uint8Array(buffer));

    return { path, fileName, md5, size: buffer.byteLength };
  }

  private async hasUploadedMarker(cacheDir: string, analyType: number): Promise<boolean> {
    const markerPath = this.getMarkerPath(cacheDir);

    try {
      await this.fs.stat(markerPath);
      return true;
    } catch {
      return false;
    }
  }

  private async writeUploadedMarker(cacheDir: string, analyType: number): Promise<void> {
    const markerPath = this.getMarkerPath(cacheDir);
    const content = JSON.stringify({ analy_type: analyType, time: Date.now() });

    await safeFileOperation(() => this.fs.writeFile(markerPath, content));
  }

  private getMarkerPath(cacheDir: string): string {
    const baseDir = cacheDir.replace(/[/\\]$/, '');
    return this.fs.join(baseDir, MARKER_FILE_NAME);
  }
}
