import { APMConfig, UploadInfo } from '../kapm_config/types';
import { BaseInfoData, BusInfoDataType, ReportPayload, ReportAttachment, AnalyTypeEnum, CrashBranchEnum,
  ANALY_TYPE_NAME_MAP } from './uploadTypes';
import { BuildCrashRecordParams, BuildAppFreezeRecordParams, BuildReportPayloadArgs } from './reportTypes';
import { buffer } from '@kit.ArkTS';

/**
 * buildPayload 方法的参数接口
 */
export interface BuildPayloadParams {
  /** 缓存目录路径 */
  cacheDir?: string;
  /** 上传时间戳，默认为当前时间 */
  uploadTimestamp?: number;
  /** 附件列表，可选 */
  attachments?: ReportAttachment[];
  /** 额外数据，可选 */
  extra?: Record<string, string | number | boolean>;
}
/**
 * ReportPayloadBuilder 类
 * 提供构建各种类型APM报告载荷的功能
 */
export class ReportPayloadBuilder {
  private config: APMConfig;

  /**
   * 构造函数
   * @param config APM配置对象
   */
  constructor(config: APMConfig) {
    this.config = config;
  }

  private _baseInfo?: BaseInfoData;
  private _busInfo?: BusInfoDataType;

  buildBaseInfo(info: UploadInfo): ReportPayloadBuilder {
    this._baseInfo = {
      _aid: info.userId,
      _did: this.config.deviceId,
      _ch: this.config.channel,
      _biz: info.businessTag,
      _av: this.config.appVersion,
      _sv: this.config.sdkVersion,
      _at: this.config.appType,
      _appid: this.config.appId,
      _brand: this.config.brand,
      _os: this.config.os,
      _ov: this.config.osVersion,
      _pid: info.processId,
      _tid: info.threadId,
      _screen: this.config.screen,
      _network: info.network,
      _carrier: info.carrier,
      _bg: info.isBackground,
      _reg: info.region,
      _uuid: info.sessionId,
      _d_type: this.config.deviceType,
      _ut: Date.now(),
    };
    return this;
  }

  private getBaseInfo(uploadTimestamp?: number): BaseInfoData {
    if (!this._baseInfo) {
      throw new Error('BaseInfoData not built');
    }
    this._baseInfo._ut = uploadTimestamp ?? Date.now();
    return this._baseInfo;
  }

  private buildGeneralBusInfo(analyType: number, eventTime: number, content: Record<string, string | number | boolean | undefined>, analyBranch?: number): ReportPayloadBuilder {
    // 构建通用内容字段
    const _content: Record<string, string | number | boolean | undefined> = {
      /** 通用字段 */
      "debug": this.config.isDebug ?? true,
      "bundle_name": this.config.bundleName,
      "kernel_version": this.config.kernelVersion,
      "build_id": this.config.buildId,
      "product_name": this.config.productName,

      /** 版本控制字段 */
      "branch_name": this.config.branchName,
      "commit_revision": this.config.commitRevision,
    };

    // 合并传入的内容字段
    Object.keys(content).forEach((key) => {
      _content[key] = content[key];
    });

    // 合并 config.extras 字段
    if (this.config.extras) {
      Object.keys(this.config.extras).forEach((key) => {
        _content[key] = this.config.extras?.[key];
      });
    }

    this._busInfo = {
      _analy_type: analyType,
      _analy_branch: analyBranch,
      _ct: eventTime,
      contents: [_content],
    };
    return this;
  }

  private getBusInfo(): BusInfoDataType {
    if (!this._busInfo) {
      throw new Error('BusInfoData not built');
    }
    return this._busInfo;
  }

  buildCrashBusInfo(analyBranch: CrashBranchEnum, eventTimestamp: number, params: Partial<BuildCrashRecordParams>): ReportPayloadBuilder {
    this.buildGeneralBusInfo(AnalyTypeEnum.Crash, eventTimestamp, {
      "fingerprint": params.fingerprint,
      "crash_type": params.crash_type,
      "crash_id": this.createEventId(ANALY_TYPE_NAME_MAP[AnalyTypeEnum.Crash], eventTimestamp),
      "crash_name": params.crash_name,
      "crash_reason": params.crash_reason,
    }, analyBranch);
    return this;
  }

  buildAppFreezeBusInfo(eventTimestamp: number, params: Partial<BuildAppFreezeRecordParams>): ReportPayloadBuilder {
    this.buildGeneralBusInfo(AnalyTypeEnum.AppFreeze, eventTimestamp, {
      "fingerprint": params.fingerprint,
      "freeze_id": this.createEventId(ANALY_TYPE_NAME_MAP[AnalyTypeEnum.AppFreeze], eventTimestamp),
      "freeze_duration": params.freeze_duration,
      "freeze_name": params.freeze_name,
      "freeze_reason": params.freeze_reason,
    }, undefined);
    return this;
  }

  /**
   * 构建最终的报告载荷
   */
  buildPayload(params: BuildPayloadParams): ReportPayload {
    const cacheDir = params.cacheDir;
    const uploadTimestamp = params.uploadTimestamp ?? Date.now();
    const attachments = params.attachments;
    const extra = params.extra;

    const payload: ReportPayload = {
      base: this.getBaseInfo(uploadTimestamp),
      bus: this.getBusInfo(),
      extra,
      attachments,
      cacheDir: cacheDir ?? '',
    };
    this._baseInfo = undefined;
    this._busInfo = undefined;

    return payload;
  }

  private createEventId(eventType: string, timestamp: number = Date.now()): string {
    const id = `${eventType}-${timestamp}-${Math.random().toString(36).substr(2, 9)}`;
    return buffer.from(id).toString('hex');
  }
}