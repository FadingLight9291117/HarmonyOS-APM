import { createDefaultNetworkClient, HttpError, NetworkClient } from '../platform/NetworkClient';
import {
  HttpResponse,
  AskRespData,
  UploadResp,
  ServerStrategy,
  UploadFilePayload,
  FilePrepareResult,
  CreateMultiPartResult,
  CreateMultiPartBody,
  MultiPartInfo,
  MultiPartCompleteBody,
  QueryParams
} from '../types/networkTypes';
import { getFileSystem } from '../platform/FileSystem';
import { getLogger } from '../utils/log/Logger';
import { Crypto } from '../platform/Crypto';
import { humanizeBytes, withTiming } from '../utils';
import { APMConfig } from '../kapm_config/types';
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * API 端点路径常量，用于构建完整的 API URL
 */
enum API_ENDPOINTS {
  // 数据上报相关接口
  DATA_UPLOAD = '/api/v1/collect/data',
  FILE_UPLOAD = '/api/v1/collect/file',

  // 分片上传相关接口
  MULTIPART_CREATE = '/api/v1/collect/multipart/create',
  MULTIPART_UPLOAD = '/api/v1/collect/multipart/upload',
  MULTIPART_COMPLETE = '/api/v1/collect/multipart/complete',

  // Token获取策略查询
  ASK = '/api/v1/ask',
};



export class NetworkService {
  private TAG = 'NetworkService';
  private log = getLogger('NetworkService');
  private readonly UPLOAD_LIMIT_MB = 10 * 1024 * 1024; // 10M
  private client: NetworkClient;
  private clientInfo: Record<string, string>;
  private latestStrategies: ServerStrategy | null = null;
  private config: APMConfig;
  private baseURL: string;

  constructor(config: APMConfig, client?: NetworkClient) {
    this.log.debug('NetworkService initialized with config', JSON.stringify({ baseURL: config.baseURL }));
    this.config = config
    this.baseURL = this.config.baseURL;
    this.client = client || createDefaultNetworkClient();
    this.clientInfo = {
      'Client-Type': this.config.appType,
      'Client-Chan': this.config.channel,
      'Client-Ver': this.config.appVersion,
    };
  }

  registerNetConnListen(callback: () => void) {
    this.log.info("registerNetConnListen")
    const netCon: connection.NetConnection = connection.createNetConnection();
    // 先使用register接口注册订阅事件
    netCon.register((error: BusinessError) => {
      if (error) {
        this.log.error(JSON.stringify(error))
      }
    });
    netCon.on("netAvailable", (data: connection.NetHandle) => {
      this.log.info("Network is available now.")
      callback();
    });
  }

  async isConnectAvailable(): Promise<boolean> {
    return await connection.hasDefaultNet()
  }

  /**
   * 构建完整的 API URL
   * @param baseURL 基础 URL
   * @param endpoint API 端点路径
   * @returns 完整的 API URL
   */
  private buildApiUrl(endpoint: string): string {
    return `${this.baseURL}${endpoint}`;
  }

  private mergeHeaders(...customHeaders: Record<string, string>[]): Record<string, string> {
    const headers: Record<string, string> = {};
    for (let i = 0; i < customHeaders.length; i++) {
      const ch = customHeaders[i];
      for (const k of Object.keys(ch)) {
        if (ch[k]) {
          headers[k] = ch[k];
        }
      }
    }
    return headers;
  }

  async uploadData(payload: string, token: string) {
    const url = this.buildApiUrl(API_ENDPOINTS.DATA_UPLOAD);
    const headers = this.mergeHeaders(this.clientInfo, {
      'Content-Type': 'application/json',
      'x-m-token': token,
    });

    try {
      const resp = await this.client.post(url, payload, headers);
      if (!resp.ok) {
        this.log.error('uploadData:http_error',
          JSON.stringify({ status: resp.status, errRes: resp.json<object>() }));
        throw new Error(`HTTP ${resp.status}`);
      }
      const result = resp.json<HttpResponse<UploadResp>>();
      if (result?.code === 0) {
        this.log.debug('uploadData:done', JSON.stringify({
          url,
          code: result.code,
          msg: result.msg,
          data: result.data
        }));
        return result.data || null;
      }
      throw new Error(result?.msg || `code ${result?.code}`);
    } catch (e) {
      this.log.error('uploadData:error', e.stack);
      return null;
    }
  }

  private async prepareFileContent(zipPath: string): Promise<FilePrepareResult> {
    const fs = getFileSystem();
    if (!await fs.exists(zipPath)) {
      this.log.error('prepareFileContent:not_exist', JSON.stringify({ zipPath }));
      return { fileContent: null, fileSize: 0, fileMd5: '' };
    }

    const fileContent = await fs.readFileAsBinary(zipPath);
    return {
      fileContent,
      fileSize: fileContent.byteLength,
      fileMd5: await Crypto.md5(new Uint8Array(fileContent)),
    };
  }

  /**
   * 统一文件上报入口（公开）: 自动根据文件大小选择单请求或分片。
   * 外部仅调用此方法; 内部再分流至 private uploadFileSingle / uploadFileMultipart。
   */
  async uploadFile(zipPath: string, token: string, payload: UploadFilePayload): Promise<UploadResp | null> {
    this.log.info('uploadFile:start', JSON.stringify({ zipPath, name: payload.name }));
    try {
      const fileInfo = await this.prepareFileContent(zipPath);
      if (!fileInfo.fileContent) throw new Error('file not exist');
      this.log.debug('uploadFile:prepare_done', JSON.stringify(fileInfo));

      if (fileInfo.fileSize > this.UPLOAD_LIMIT_MB) {
        this.log.info('uploadFile:file_too_large', JSON.stringify({ zipPath, fileSize: humanizeBytes(fileInfo.fileSize) }));
        return await withTiming(`${this.TAG}:uploadFileMultipart`, () => this.uploadFileMultipart(fileInfo, payload, token));
      } else {
        this.log.info('uploadFile:file_size_ok', JSON.stringify({ zipPath, fileSize: humanizeBytes(fileInfo.fileSize) }));
        return await withTiming(`${this.TAG}:uploadFileSingle`, () => this.uploadFileSingle(fileInfo, payload, token));
      }
    } catch (e) {
      this.log.error(`uploadFile:error ${e.message} ${e.stack}`);
      return null;
    }
  }

  async ask(): Promise<AskRespData | null> {
    const url = this.buildApiUrl(API_ENDPOINTS.ASK);
    const query: QueryParams = { "appid": this.config.appId };
    const headers = this.mergeHeaders(this.clientInfo);

    try {
      const resp = await this.client.get(url, headers, query);
      if (!resp.ok) throw new HttpError('Ask', resp);

      const result = resp.json<HttpResponse<AskRespData>>();
      if (result?.code !== 0) throw new Error(result?.msg || `code ${result?.code}`);

      if (result.data?.strategy) {
        this.latestStrategies = ServerStrategy.of(result.data.strategy);
      }
      this.log.debug('ask:done', JSON.stringify({ url, code: result.code }));
      return result.data || null;
    } catch (e) {
      this.log.error(`ask:error ${e.message} ${e.stack}`);
      return null;
    }
  }

  /**
   * 分片上传实现 (内部使用). 触发条件: size > 10MB.
   * 流程:
   * 1. 创建分片上传会话 /multipart/create
   * 2. 文件切片并逐片上传 /multipart/upload （带重试）
   * 3. 全部分片成功后调用 /multipart/complete
   */
  private async uploadFileMultipart(fileInfo: FilePrepareResult, payload: UploadFilePayload, token: string): Promise<UploadResp | null> {
    try {
      if (!fileInfo.fileContent) throw new Error('file not exist');
      this.log.debug('uploadFileMultipart:start', JSON.stringify({ name: payload.name, size: fileInfo.fileSize, md5: fileInfo.fileMd5 }));

      const multiPartInfo = await this.createMultipart(fileInfo, payload, token);
      const uploadId = multiPartInfo.upload_id;
      const partSize = multiPartInfo.part_size;
      const parts = await this.splitFileToParts(fileInfo, partSize);
      for (const p of parts) {
        await this.uploadPartWithRetry(fileInfo, uploadId, p, token);
      }
      const result = await this.completeMultipart(fileInfo, uploadId, token);
      this.log.debug('uploadFileMultipart:done', JSON.stringify({ uploadId: uploadId, name: payload.name, size: fileInfo.fileSize }));
      return result;
    } catch (e) {
      this.log.error(`uploadFileMultipart:error ${e.message}`);
      return null;
    }
  }

  private async createMultipart(fileInfo: FilePrepareResult, payload: UploadFilePayload, token: string): Promise<CreateMultiPartResult> {
    this.log.debug('createMultipart:start', JSON.stringify({ name: payload.name, size: fileInfo.fileSize, md5: fileInfo.fileMd5 }));
    const url = this.buildApiUrl(API_ENDPOINTS.MULTIPART_CREATE);
    const headers: Record<string, string> = this.mergeHeaders(this.clientInfo, { 'Content-Type': 'application/json', 'x-m-token': token });
    const body: CreateMultiPartBody = {
      name: payload.name,
      md5: fileInfo.fileMd5,
      size: fileInfo.fileSize,
      type: payload.type,
      type_branch: payload.type_branch,
      encrypt_ver: payload.encrypt_ver
    };
    const resp = await this.client.post(url, JSON.stringify(body), headers);
    if (!resp.ok) throw new HttpError('MultipartCreate', resp);
    const obj = resp.json<HttpResponse<CreateMultiPartResult>>();
    if (!obj || obj.code !== 0 || !obj.data || !obj.data.upload_id) {
      throw new Error(obj ? (obj.msg || ('code ' + obj.code)) : 'multipart create failed');
    }
    const uploadId = obj.data.upload_id;
    const partSize = (obj.data.part_size && obj.data.part_size > 0) ? obj.data.part_size : (5 * 1024 * 1024);
    return { upload_id: uploadId, part_size: partSize };
  }

  private async splitFileToParts(fileInfo: FilePrepareResult, partSize: number): Promise<MultiPartInfo[]> {
    if (!fileInfo.fileContent) throw new Error('file content is null');
    const fileBuf = new Uint8Array(fileInfo.fileContent)
    const totalSize = fileBuf.length;
    const parts: MultiPartInfo[] = [];
    let offset = 0;
    let idx = 1;
    while (offset < totalSize) {
      const end = Math.min(offset + partSize, totalSize);
      const slice: Uint8Array = fileBuf.slice(offset, end);
      parts.push({ index: idx, buf: slice });
      offset = end;
      idx += 1;
    }
    return parts;
  }

  private async uploadPartWithRetry(fileInfo: FilePrepareResult, uploadId: string, part: MultiPartInfo, token: string): Promise<void> {
    const uploadUrl = this.buildApiUrl(API_ENDPOINTS.MULTIPART_UPLOAD);
    const maxRetries = 3;
    let attempt = 0;
    while (attempt < maxRetries) {
      attempt += 1;
      this.log.debug('uploadFileMultipart:uploadPart', JSON.stringify({ uploadId: uploadId, part: part.index, attempt }));
      const partMd5 = await Crypto.md5(part.buf);
      const query: Record<string, string | number> = {
        "md5": fileInfo.fileMd5,
        "upload_id": uploadId,
        "part_number": part.index,
        "part_size": part.buf.length,
        "part_md5": partMd5
      };
      try {
        const partHeaders: Record<string, string> = this.mergeHeaders(this.clientInfo, { 'Content-Type': 'application/zip', 'x-m-token': token });
        const resp = await this.client.post(uploadUrl, part.buf.buffer, partHeaders, query);
        if (!resp.ok) throw new HttpError('UploadPart', resp);
        const obj = resp.json<HttpResponse<null>>();
        if (!obj || obj.code !== 0) throw new Error(obj ? (obj.msg || ('code ' + obj.code)) : 'part upload failed');
        this.log.debug('uploadFileMultipart:uploadPartDone', JSON.stringify({ uploadId: uploadId, part: part.index }));
        return;
      } catch (err) {
        this.log.error('uploadFileMultipart:uploadPartRetry', err);
        if (attempt >= maxRetries) throw err as Error;
        await this.delay(500 * attempt);
      }
    }
  }

  private async completeMultipart(fileInfo: FilePrepareResult, uploadId: string, token: string): Promise<UploadResp | null> {
    this.log.debug('completeMultipart:start', JSON.stringify({ uploadId: uploadId, md5: fileInfo.fileMd5 }));
    const completeUrl = this.buildApiUrl(API_ENDPOINTS.MULTIPART_COMPLETE);
    const headers: Record<string, string> = this.mergeHeaders(this.clientInfo, { 'Content-Type': 'application/json', 'x-m-token': token });
    const completeBody: MultiPartCompleteBody = { md5: fileInfo.fileMd5, upload_id: uploadId };
    const resp = await this.client.post(completeUrl, JSON.stringify(completeBody), headers);
    if (!resp.ok) throw new HttpError('MultipartComplete', resp);
    const obj = resp.json<HttpResponse<UploadResp>>();
    if (!obj || obj.code !== 0) {
      throw new Error(obj ? (obj.msg || ('code ' + obj.code)) : 'multipart complete failed');
    }
    return obj.data || null;
  }


  /**
   * 单文件直接上传实现 (内部使用)。
   */
  private async uploadFileSingle(fileInfo: FilePrepareResult, payload: UploadFilePayload, token: string): Promise<UploadResp | null> {
    try {
      if (!fileInfo.fileContent) throw new Error('file not exist');
      this.log.debug('uploadFileSingle:start', JSON.stringify({ name: payload.name, size: fileInfo.fileSize, md5: fileInfo.fileMd5 }));

      const url = this.buildApiUrl(API_ENDPOINTS.FILE_UPLOAD);
      const headers = this.mergeHeaders(this.clientInfo, { 'Content-Type': 'application/zip', 'x-m-token': token });
      const query: QueryParams = {
        "name": payload.name,
        "md5": fileInfo.fileMd5,
        "size": fileInfo.fileSize,
        "type": payload.type,
        "type_branch": payload.type_branch,
        "encrypt_ver": payload.encrypt_ver,
        "extra": payload.extra,
      };

      const resp = await this.client.post(url, fileInfo.fileContent, headers, query);
      if (!resp.ok) throw new HttpError('UploadSingle', resp);
      const result = resp.json<HttpResponse<UploadResp>>();
      if (result?.code !== 0) throw new Error(result?.msg || `code ${result?.code}`);
      this.log.debug('uploadFileSingle:done', JSON.stringify({ name: payload.name, size: humanizeBytes(fileInfo.fileSize) }));
      return result.data || null;
    } catch (e) {
      this.log.error(`uploadFileSingle:error ${e.message}`);
      return null;
    }
  }

  getServerStrategies(): ServerStrategy | null {
    return this.latestStrategies;
  }

  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
