import { NetworkService } from '../services/NetworkService';
import { TokenService } from '../services/TokenService';
import { CacheService } from '../services/CacheService';
import { ReportService, ReportSkippedResult } from '../services/ReportService';
import { EncryptCompressService } from '../services/EncryptCompressService';
import { getLogger } from '../utils/log/Logger';
import { MetricKeys, Monitor } from '../utils/Monitor';
import { APMConfigManager } from '../kapm_config/APMConfigManager';
import { BaseInfoData, BusInfoDataType, ReportAttachment, ReportPayload } from '../types/uploadTypes';
import { withTiming } from '../utils';
import { APMConfig } from '../kapm_config/types';
import { AppMonitorService } from '../services/AppMonitorService';
import { CacheScanUploadService } from '../services/CacheScanUploadService';
import { NativeCrashService } from '../services/NativeCrashService';

export class APMCore {
  private readonly TAG = 'APMCore';
  private readonly log = getLogger(this.TAG);
  private static instance: APMCore | null = null;
  private static isInitialized: boolean = false;
  private context: Context;
  private config: APMConfig;
  private networkService: NetworkService;
  private tokenService: TokenService;
  private cacheService: CacheService;
  private reportService: ReportService;
  private appMonitorService: AppMonitorService;
  private scanUploadService: CacheScanUploadService;
  private nativeCrashService: NativeCrashService;
  private monitor: Monitor;
  // config
  private disableAutoCleanup: boolean = false;
  private isScanning: boolean = false;


  private constructor(context: Context, overrides: Partial<APMConfig> = {}) {
    this.context = context;
    // APMConfigManager now validates config in its constructor
    APMConfigManager.getInstance().setConfig(overrides);
    this.config = APMConfigManager.getInstance().getConfig();
    this.networkService = new NetworkService(this.config);
    this.tokenService = new TokenService(this.config, this.networkService);
    this.cacheService = new CacheService(this.config);
    this.monitor = new Monitor();
    // Initialize encryption service with configured keys
    const ecService = new EncryptCompressService(this.context, {
      keyHex: this.config.keys[0],
      iv: this.config.keys[1]},
    );
    // Initialize ReportService with all dependencies
    this.reportService = new ReportService({
      networkService: this.networkService,
      tokenService: this.tokenService,
      ecService: ecService,
      retryInterval: this.config.retryInterval ?? 1000,
      maxRetryCount: this.config.maxRetryCount ?? 3,
      shouldEncrypt: this.config.enableEncryptTransfer,
      encryptVersion: this.config.encrypt_ver,
    });
    this.appMonitorService = new AppMonitorService(this.cacheService);
    this.nativeCrashService = new NativeCrashService(this.cacheService);
    this.scanUploadService = new CacheScanUploadService({
      cacheService: this.cacheService,
      reportService: this.reportService,
      config: this.config
    });
    // config
    this.disableAutoCleanup = this.config.disableAutoCleanup ?? false

    this.log.debug('APMCore initialized with config:', JSON.stringify(this.config));
  }

  /**
   * Initialize the APMCore singleton with configuration.
   */
  static init(context: Context, overrides: Partial<APMConfig> = {}): APMCore {
    if (APMCore.isInitialized) {
      throw new Error('APMCore is already initialized. Use APMCore.getInstance() instead.');
    }

    const instance = new APMCore(context, overrides);
    instance
      .startAppMonitoring()                             // 1. Start AppMonitorService to begin monitoring events
      // .startNativeCrashHandler()                        // 2. Start NativeCrashService to handle native crashes
      .startScheduledCleanup()                          // 3. Start scheduled cache cleanup task.
      .then(() => { instance.scanCacheAndUpload() });   // 4. Start initial scan and upload of pending reports.
    instance.startNetConListen();                       // 5. Start Network Connection Listener to trigger uploads on connectivity.

    APMCore.instance = instance;
    APMCore.isInitialized = true;

    return APMCore.instance;
  }

  private startNetConListen() {
    this.log.info("Starting Network Conn Listen Service");
    this.networkService.registerNetConnListen(() => {
      this.log.info("Network is Available");
      this.scanCacheAndUpload();
    });
    return this;
  }

  private startAppMonitoring() {
    this.log.info('Starting App Monitor Service');
    this.appMonitorService.start(this.context)
    return this;
  }

  private startNativeCrashHandler() {
    this.log.info('Starting Native Crash Handler Service');
    this.nativeCrashService.start();
    return this;
  }

  /**
   * Start scheduled cache cleanup task.
   */
  private async startScheduledCleanup() {
    await this.delay(3 * 1000);
    if (this.disableAutoCleanup) return this; // Skip cleanup if disabled
    this.log.info('Starting scheduled cache cleanup task');
    this.cacheService.startScheduledCleanup();
    return this;
  }

  /**
   * Scan cache and upload cached reports.
   */
  private async scanCacheAndUpload() {
    if (!await this.networkService.isConnectAvailable()) {
      this.log.warn('Network not available, skipping scanCacheAndUpload');
      return this
    }
    if (this.isScanning) return
    this.isScanning = true
    this.log.info('Starting cache scan and upload of pending reports');
    try {
      await this.cacheService.waitForIdle();
      await withTiming(`${this.TAG}:scanCacheAndUpload`, () => this.scanUploadService.scanAndUpload());
    } catch (error) {
      this.log.error('Error during cache scan and upload', error);
    } finally {
      this.isScanning = false;
    }
    return this;
  }

  /**
   * Get the APMCore singleton instance.
   * @throws Error if not initialized yet
   */
  static getInstance(): APMCore {
    if (!APMCore.isInitialized || APMCore.instance === null) {
      throw new Error('APMCore is not initialized. Call APMCore.init() first.');
    }
    return APMCore.instance;
  }

  /**
   * Check if APMCore has been initialized.
   */
  static isReady(): boolean {
    return APMCore.isInitialized && APMCore.instance !== null;
  }

  /**
   * Reset the singleton instance (mainly for testing purposes).
   * @internal
   */
  static reset(): void {
    // Stop scheduled cleanup to avoid lingering timers in tests
    if (APMCore.instance) {
      APMCore.instance.cacheService.stopScheduledCleanup();
    }
    APMCore.instance = null;
    APMCore.isInitialized = false;
  }

  /**
   * Ensure the instance is initialized before calling instance methods.
   * @throws Error if not initialized
   */
  private ensureInitialized(): void {
    if (!APMCore.isInitialized) {
      throw new Error('APMCore is not initialized. Call APMCore.init() first.');
    }
  }

  /**
   * Report data with file attachments as a ZIP package.
   * @returns Upload result or throws error
   */
  async reportFile(payload: ReportPayload, source: string): Promise<ReportSkippedResult> {
    if (!await this.networkService.isConnectAvailable()) {
      this.monitor.inc(MetricKeys.ReportFailed);
      this.log.warn('File upload failed', JSON.stringify({
        analyType: payload.bus._analy_type,
        attachments: payload.attachments?.length || 0,
        reason: 'Network not available',
        source,
      }));
      return {
        success: false,
        skipped: true,
        reason: 'Network not available'
      };
    }
    return withTiming(`${this.TAG}:reportFile`, async () => {
      this.ensureInitialized();
      const base: BaseInfoData = payload.base
      const bus: BusInfoDataType = payload.bus
      const cacheDir: string = payload.cacheDir
      const extra: Record<string, string | number | boolean> | undefined = payload.extra
      const attachments: ReportAttachment[] | undefined = payload.attachments

      // wait for any cache clean operations to complete, if cache cleanup is ongoing
      await this.cacheService.waitForIdle();
      this.monitor.inc(MetricKeys.ReportTotal);

      try {
        this.log.debug('Building payoad with attachments', JSON.stringify({
          analyType: bus._analy_type,
          attachmentCount: attachments?.length || 0
        }));

        // Build payload using ReportService
        // buildPayload signature: (base, bus, cacheDir, extra, attachments)
        const payload = this.reportService.buildPayload(base, bus, cacheDir, extra, attachments);

        // ReportService now handles retry and token invalidation
        const reportResult = await this.reportService.reportZip(payload);

        if (reportResult.success) {
          this.monitor.inc(MetricKeys.ReportSuccess);
          this.log.info('File upload success', JSON.stringify({
            analyType: bus._analy_type,
            attachments: attachments?.length || 0,
            reason: reportResult.reason,
            source,
          }));
        } else {
          this.monitor.inc(MetricKeys.ReportFailed);
          this.log.error('File upload failed', JSON.stringify({
            analyType: bus._analy_type,
            attachments: attachments?.length || 0,
            reason: reportResult.reason,
            source,
          }));
        }

        return reportResult;
      } catch (err) {
        this.monitor.inc(MetricKeys.ReportFailed);
        this.log.error('File upload failed', err.message || err);
        throw err as Error;
      }
    });
  }

  /**
   * Get current metrics snapshot.
   */
  getMetrics() {
    return this.monitor.get();
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}