import { NetworkService } from '../services/NetworkService';
import { TokenService } from '../services/TokenService';
import { CacheService } from '../services/CacheService';
import { ReportService, ReportSkippedResult } from '../services/ReportService';
import { EncryptCompressService } from '../services/EncryptCompressService';
import { getLogger } from '../utils/log/Logger';
import { APMConfigManager } from '../kapm_config/APMConfigManager';
import { ReportPayload } from '../types/uploadTypes';
import { withTiming } from '../utils';
import { APMConfig } from '../kapm_config/types';
import { AppMonitorService } from '../services/AppMonitorService';
import { CacheScanUploadService } from '../services/CacheScanUploadService';
import { NativeCrashService } from '../services/NativeCrashService';
import { errorManager } from '@kit.AbilityKit';

// 常量定义
const DEFAULT_RETRY_INTERVAL = 1000;
const DEFAULT_MAX_RETRY_COUNT = 3;
const CLEANUP_DELAY_MS = 3000;

export class APMCore {
  private static readonly TAG = 'APMCore';
  private readonly log = getLogger(APMCore.TAG);
  private static instance: APMCore | null = null;
  private static isInitialized = false;
  // Services
  static config: APMConfig;
  private readonly networkService: NetworkService;
  private readonly tokenService: TokenService;
  private readonly cacheService: CacheService;
  private readonly reportService: ReportService;
  private readonly appMonitorService: AppMonitorService;
  private readonly scanUploadService: CacheScanUploadService;
  private readonly nativeCrashService: NativeCrashService;
  // State
  private readonly disableAutoCleanup: boolean;
  private isScanning = false;

  private constructor(overrides: Partial<APMConfig> = {}) {
    APMConfigManager.getInstance().setConfig(overrides);
    APMCore.config = APMConfigManager.getInstance().getConfig();

    // Initialize core services
    this.networkService = new NetworkService(APMCore.config);
    this.tokenService = new TokenService(APMCore.config, this.networkService);
    this.cacheService = new CacheService(APMCore.config);

    // Initialize encryption service
    const ecService = new EncryptCompressService({
      keyHex: APMCore.config.keys[0],
      iv: APMCore.config.keys[1],
    });

    // Initialize report service
    this.reportService = new ReportService({
      networkService: this.networkService,
      tokenService: this.tokenService,
      ecService: ecService,
      retryInterval: APMCore.config.retryInterval ?? DEFAULT_RETRY_INTERVAL,
      maxRetryCount: APMCore.config.maxRetryCount ?? DEFAULT_MAX_RETRY_COUNT,
      shouldEncrypt: APMCore.config.enableEncryptTransfer,
      encryptVersion: APMCore.config.encrypt_ver,
    });

    // Initialize monitoring services
    this.appMonitorService = new AppMonitorService(this.cacheService);
    this.nativeCrashService = new NativeCrashService(this.cacheService);
    this.scanUploadService = new CacheScanUploadService({
      cacheService: this.cacheService,
      reportService: this.reportService,
      config: APMCore.config
    });

    this.disableAutoCleanup = APMCore.config.disableAutoCleanup ?? false;

    this.log.debug('APMCore initialized with config:', JSON.stringify(APMCore.config));
  }

  /**
   * Initialize the APMCore singleton with configuration.
   * @param overrides Optional configuration overrides
   * @returns Initialized APMCore instance
   * @throws Error if already initialized
   */
  static init(overrides: Partial<APMConfig> = {}): APMCore {
    if (APMCore.isInitialized) {
      throw new Error('APMCore is already initialized. Use APMCore.getInstance() instead.');
    }
    APMCore.instance = new APMCore(overrides);
    APMCore.isInitialized = true;

    return APMCore.instance;
  }

  /**
   * Start all background services in the correct order.
   */
  startCacheServices(): APMCore {
    this.startScheduledCleanup().then(() => this.scanCacheAndUpload());
    return this;
  }

  startMonitorServices(): APMCore {
    this.log.info('Starting Thread Services');
    this.startAppMonitoring();
    this.startNativeCrashHandler();
    return this;
  }

  startNetConService(): APMCore {
    this.log.info('Starting Network Connection Listener');
    this.networkService.registerNetConnListen(() => {
      this.log.info('Network is available, triggering cache upload');
      this.scanCacheAndUpload();
    });
    return this;
  }

  private startAppMonitoring(): void {
    this.log.info('Starting App Monitor Service');
    this.appMonitorService.start();
  }

  private startNativeCrashHandler(): void {
    this.log.info('Starting Native Crash Handler Service');
    this.nativeCrashService.start();
  }

  /**
   * Start scheduled cache cleanup task after initial delay.
   */
  private async startScheduledCleanup(): Promise<void> {
    await this.delay(CLEANUP_DELAY_MS);
    if (this.disableAutoCleanup) {
      this.log.info('Auto cleanup is disabled, skipping scheduled cleanup');
      return;
    }
    this.log.info('Starting scheduled cache cleanup task');
    this.cacheService.startScheduledCleanup();
  }

  /**
   * Scan cache and upload cached reports when network is available.
   */
  private async scanCacheAndUpload(): Promise<void> {
    if (!await this.networkService.isConnectAvailable()) {
      this.log.warn('Network not available, skipping cache scan and upload');
      return;
    }

    if (this.isScanning) {
      this.log.debug('Cache scan already in progress, skipping');
      return;
    }

    this.isScanning = true;
    this.log.info('Starting cache scan and upload of pending reports');

    try {
      await this.cacheService.waitForIdle();
      await withTiming(`${APMCore.TAG}:scanCacheAndUpload`, () =>
      this.scanUploadService.scanAndUpload()
      );
    } catch (error) {
      this.log.error('Error during cache scan and upload', error);
    } finally {
      this.isScanning = false;
    }
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
   * Report data with file attachments as a ZIP package.
   * This method creates its own services internally for use in Task environment.
   * @param payload Report payload containing base info, business data and attachments
   * @param source Source identifier for logging purposes
   * @returns Upload result indicating success/failure
   */
  static async reportFile(payload: ReportPayload, source: string): Promise<ReportSkippedResult> {
    const config = APMCore.config;
    if (!config) {
      throw new Error('APMCore.config is not set. Call APMCore.init() first.');
    }
    const log = getLogger(APMCore.TAG);
    const analyType: number = payload.bus._analy_type;
    const attachmentCount: number = payload.attachments?.length ?? 0;

    // Create services for Task environment
    const networkService = new NetworkService(config);
    const tokenService = new TokenService(config, networkService);
    const ecService = new EncryptCompressService({
      keyHex: config.keys[0],
      iv: config.keys[1],
    });
    const reportService = new ReportService({
      networkService: networkService,
      tokenService: tokenService,
      ecService: ecService,
      retryInterval: config.retryInterval ?? DEFAULT_RETRY_INTERVAL,
      maxRetryCount: config.maxRetryCount ?? DEFAULT_MAX_RETRY_COUNT,
      shouldEncrypt: config.enableEncryptTransfer,
      encryptVersion: config.encrypt_ver,
    });

    // Check network availability first
    if (!await networkService.isConnectAvailable()) {
      log.warn('File upload skipped - network unavailable', JSON.stringify({
        analyType: analyType,
        attachments: attachmentCount,
        source: source,
      }));
      return { success: false, skipped: true, reason: 'Network not available' };
    }

    return withTiming(`${APMCore.TAG}:reportFile`, async () => {
      try {
        log.debug('Building payload with attachments', JSON.stringify({
          analyType: analyType,
          attachmentCount: attachmentCount,
        }));

        const builtPayload = reportService.buildPayload(
          payload.base,
          payload.bus,
          payload.cacheDir,
          payload.extra,
          payload.attachments
        );
        const reportResult = await reportService.reportZip(builtPayload);

        if (reportResult.success) {
          log.info('File upload success', JSON.stringify({
            analyType: analyType,
            attachments: attachmentCount,
            reason: reportResult.reason,
            source: source,
          }))
        } else {
          log.error('File upload failed', JSON.stringify({
            analyType: analyType,
            attachments: attachmentCount,
            reason: reportResult.reason,
            source: source,
          }))
        }
        return reportResult;
      } catch (err) {
        log.error('File upload failed with exception', err.message);
        throw err as Error;
      }
    });
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  onError(observer: (reason: Error) => void): void {
    try {
      errorManager.on('globalUnhandledRejectionDetected', observer)
      errorManager.on("globalErrorOccurred", observer);
      return
    } catch (e) {
      this.log.warn("Failed to use new api, so compatibility mode is enabled.");
      try {
        errorManager.on('error', {
          onUnhandledException: () => {},
          onException: observer,
        })
        errorManager.on("unhandledRejection", observer);
      } catch (error) {
        this.log.error('Error registering JS error observer:', error.message);
      }
    }
  }
}

