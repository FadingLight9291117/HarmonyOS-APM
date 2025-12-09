import { getLogger } from '../utils';
import { getFileSystem } from '../platform/FileSystem';
import { CacheService } from './CacheService';
import { ReportService } from './ReportService';
import { EventWithFiles } from '../kapm_cache/use/types';
import { CrashBranchEnum, ReportAttachment } from '../types/uploadTypes';
import { ReportPayloadBuilder } from '../types/reportPayloadBuilders';
import { EventInfoParams, CachedFileMeta } from '../kapm_cache/save/types';
import { APMConfig, UploadInfo } from '../kapm_config/types';
import { EventType } from '../kapm_data_collection/event/EventChannel';
import { APMCore } from '../kapm_core/APMCore';

interface ScanUploadError {
  eventDir: string;
  error: string;
}

interface ScanUploadStats {
  scanned: number;
  uploaded: number;
  skipped: number;
  failed: number;
  errors: Array<ScanUploadError>;
}

interface EventInfo {
  base: string;
  analyType: number;
  fileCount: number;
}

interface EventUploadResult {
  status: EventUploadStatus;
  event: EventInfo;
  error?: string;
}

enum EventUploadStatus {
  UPLOADED = 'uploaded',
  SKIPPED = 'skipped',
  FAILED = 'failed'
}

export interface CacheScanUploadOptions {
  maxEvents?: number;
  skipUploaded?: boolean;
}

export interface CacheScanUploadServiceParams {
  cacheService: CacheService;
  reportService: ReportService;
  config: APMConfig;
}

/**
 * CacheScanUploadService handles scanning cached events and uploading them.
 * Separates cache scanning/iteration logic from the core ReportService.
 */
export class CacheScanUploadService {
  private log = getLogger('CacheScanUploadService');
  private fs = getFileSystem();
  private payloadBuilder: ReportPayloadBuilder;
  private cacheService: CacheService;
  private reportService: ReportService;
  private config: APMConfig;

  constructor(params: CacheScanUploadServiceParams) {
    this.cacheService = params.cacheService;
    this.reportService = params.reportService;
    this.config = params.config;
    this.payloadBuilder = new ReportPayloadBuilder(params.config);
  }

  /**
   * Scan cache and upload pending events that haven't been uploaded yet.
   *
   * @param options.maxEvents Maximum number of events to upload (default: unlimited)
   * @param options.skipUploaded Skip events with upload marker (default: true)
   * @returns Summary of scan and upload operations
   */
  async scanAndUpload(options: CacheScanUploadOptions = {}): Promise<ScanUploadStats> {
    const maxEvents = options.maxEvents ?? Infinity;
    const skipUploaded = options.skipUploaded ?? true;

    this.log.info('scanAndUpload: starting', JSON.stringify({ maxEvents, skipUploaded }));

    await this.cacheService.buildUsageIndex({ skipUploaded });

    const stats = this.createStats();

    while (stats.scanned < maxEvents) {
      const event = await this.cacheService.nextCacheGroup();
      this.log.debug("scanAndUpload: " + JSON.stringify(event))
      if (!event) {
        break;
      }

      stats.scanned++;

      const result = await this.processEvent(event, skipUploaded);
      this.updateStats(stats, result);
    }

    this.log.info('scanAndUpload: completed', JSON.stringify(stats));
    return stats;
  }

  private createStats(): ScanUploadStats {
    return {
      scanned: 0,
      uploaded: 0,
      skipped: 0,
      failed: 0,
      errors: []
    };
  }

  private async processEvent(event: EventWithFiles, skipUploaded: boolean): Promise<EventUploadResult> {
    try {
      // Skip already uploaded events
      if (skipUploaded && event.hasUploaded) {
        this.logSkipped(event);
        return {
          status: EventUploadStatus.SKIPPED,
          event: this.extractEventInfo(event)
        };
      }

      // Build and upload payload
      const eventDir = this.getEventDirectory(event);
      const payload = await this.buildPayload(event, eventDir);
      const result = await APMCore.getInstance().reportFile(payload, "ScanUploadService");

      if (result.success) {
        this.logUploaded(event);
        return {
          status: EventUploadStatus.UPLOADED,
          event: this.extractEventInfo(event)
        };
      } else if (result.skipped) {
        return {
          status: EventUploadStatus.SKIPPED,
          event: this.extractEventInfo(event)
        };
      } else {
        return {
          status: EventUploadStatus.FAILED,
          event: this.extractEventInfo(event),
          error: result.reason || 'Unknown error'
        };
      }
    } catch (error) {
      this.logFailed(event, error.message);
      return {
        status: EventUploadStatus.FAILED,
        event: this.extractEventInfo(event),
        error: error.message,
      };
    }
  }

  private getEventDirectory(event: EventWithFiles): string {
    return this.fs.parent(event.attachments[0] || '');
  }

  private extractEventInfo(event: EventWithFiles): EventInfo {
    return {
      base: event.base,
      analyType: event.analyType,
      fileCount: event.attachmentCount
    };
  }

  private buildFallbackUploadInfo(eventInfo: EventInfoParams): UploadInfo {
    return {
      timestamp: eventInfo.time,
      processId: eventInfo.pid ? String(eventInfo.pid) : '',
      isBackground: !eventInfo.foreground
    };
  }

  private updateStats(stats: ScanUploadStats, result: EventUploadResult): void {
    switch (result.status) {
      case 'uploaded':
        stats.uploaded++;
        break;
      case 'skipped':
        stats.skipped++;
        break;
      case 'failed':
        stats.failed++;
        stats.errors.push({
          eventDir: result.event.base,
          error: result.error || 'Unknown error'
        });
        break;
    }
  }

  /**
   * Build a ReportPayload from EventWithFiles structure.
   * This method:
   * 1. Reads the .json file to get EventInfoParams
   * 2. Reads the .meta file (if exists) to get UploadInfo and extra
   * 3. Uses ReportPayloadBuilder to reconstruct base and bus
   * 4. Collects attachment files
   * 5. Constructs the complete ReportPayload
   */
  private async buildPayload(event: EventWithFiles, eventDir: string) {
    // Use eventInfoPath if available, otherwise find from attachments
    let eventInfoFile: string | undefined = event.eventInfoPath;

    if (!eventInfoFile) {
      // Fallback: find the JSON file from attachments (prefer exact match, then any .json)
      const expectedJsonName: string = `${event.base}.json`;
      eventInfoFile = event.attachments.find(f =>
      this.fs.basename(f) === expectedJsonName
      ) || event.attachments.find(f => f.endsWith('.json'));
    }

    if (!eventInfoFile) {
      throw new Error(`No .json file found in event: ${event.base}`);
    }

    // Read and parse the JSON file (contains EventInfoParams)
    const dataContent: string = await this.fs.readFile(eventInfoFile);
    const eventInfo: EventInfoParams = JSON.parse(dataContent) as EventInfoParams;

    // Read metadata from .meta file (if available)
    let uploadInfo: UploadInfo;
    let extra: Record<string, string | number | boolean> = {};

    if (event.metaFilePath) {
      try {
        const metaContent: string = await this.fs.readFile(event.metaFilePath);
        const meta: CachedFileMeta = JSON.parse(metaContent) as CachedFileMeta;
        uploadInfo = meta.uploadInfo;
        extra = meta.extra || {};
      } catch (error) {
        // If meta file read fails, use fallback
        this.log.warn('Failed to read meta file, using fallback', JSON.stringify({
          metaPath: event.metaFilePath,
          error: error instanceof Error ? error.message : String(error)
        }));
        uploadInfo = this.buildFallbackUploadInfo(eventInfo);
      }
    } else {
      // Fallback: construct minimal UploadInfo from eventInfo
      uploadInfo = this.buildFallbackUploadInfo(eventInfo);
    }

    // Use ReportPayloadBuilder to construct base and bus info
    this.payloadBuilder.buildBaseInfo(uploadInfo);

    // Determine analyType and build appropriate bus info based on dataType
    if (event.dataType === EventType.JS_ERROR || event.dataType === EventType.NATIVE_CRASH) {
      const crashBranch: number = event.dataType === EventType.JS_ERROR ? CrashBranchEnum.JsError : CrashBranchEnum.NativeCrash; // 0=JSError, 1=NativeCrash
      this.payloadBuilder.buildCrashBusInfo(crashBranch, event.createTime, {
        fingerprint: eventInfo.uuid,
        crash_type: event.dataType,
        crash_name: eventInfo.exception?.name,
        crash_reason: eventInfo.exception?.message,
      });
    } else if (event.dataType === EventType.APP_FREEZE) {
      this.payloadBuilder.buildAppFreezeBusInfo(event.createTime, {
        fingerprint: eventInfo.uuid,
        freeze_name: eventInfo.exception?.name,
        freeze_reason: eventInfo.exception?.message,
      });
    } else {
      // For unknown event types, use crash bus info as default
      this.log.warn('Unknown event dataType, using crash bus info as default', JSON.stringify({
        dataType: event.dataType,
        eventDir: event.base
      }));
      this.payloadBuilder.buildCrashBusInfo(0, event.createTime, {
        fingerprint: eventInfo.uuid,
        crash_type: event.dataType,
        crash_name: 'Unknown Event',
        crash_reason: 'Unknown event type'
      });
    }

    // Collect attachments (exclude .meta and .zip files)
    const attachments: ReportAttachment[] = event.attachments
      .filter(f => !f.endsWith('.zip') && !f.endsWith('.meta'))
      .map<ReportAttachment>(f => ({
        name: this.fs.basename(f),
        path: f
      }));

    // Build final payload
    return this.payloadBuilder.buildPayload({
      cacheDir: eventDir,
      uploadTimestamp: Date.now(),
      attachments,
      extra
    });
  }

  // Logging methods
  private logSkipped(event: EventWithFiles): void {
    this.log.debug('skipping already uploaded event', JSON.stringify({
      eventDir: event.base,
      analyType: event.analyType
    }));
  }

  private logUploaded(event: EventWithFiles): void {
    this.log.info('uploaded event', JSON.stringify({
      eventDir: event.base,
      analyType: event.analyType,
      fileCount: event.attachmentCount
    }));
  }

  private logFailed(event: EventWithFiles, errorMsg: string): void {
    this.log.error('failed to upload event', JSON.stringify({
      eventDir: event.base,
      analyType: event.analyType,
      fileCount: event.attachmentCount,
      error: errorMsg
    }));
  }
}

