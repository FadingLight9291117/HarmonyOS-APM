// 网络策略与响应类型定义
export interface Strategy {
  disable?: boolean;
  persent?: string; // NOTE: 保留原字段名（可能为 percent 的拼写），按源代码保持
  sendGap: string;
  totalSize: string;
}

interface StrategyTransportTactics {
  gzip: number;
  split: number;
}

type Strategies = Record<string, Strategy | StrategyTransportTactics>

export type QueryParams = Record<string, string | number | undefined>;

export interface AskRespData {
  token: string;
  token_expire_at: number;
  strategy: Strategies;
  token_expire_gap: number;
}

export interface UploadResp {
  upload_id: string;
  session_id?: string;
}

export interface HttpResponse<T> {
  code: number;
  msg: string;
  data?: T;
}

export class ServerStrategy {
  private readonly strategies: Strategies;

  private constructor(strategies: Strategies) {
    this.strategies = strategies;
  }

  static of(strategies: Strategies): ServerStrategy {
    return new ServerStrategy(strategies);
  }

  getTransportTactics(): StrategyTransportTactics | null {
    if (!this.strategies['transportTactics']) {
      return null
    }
    return this.strategies['transportTactics'] as StrategyTransportTactics;
  }

  getStrategy(name: string): Strategy | null {
    if (!this.strategies[name]) {
      return null
    }
    return this.strategies[name] as Strategy;
  }
}

export interface UploadFilePayload {
  name: string;
  type: number;
  type_branch?: number;
  encrypt_ver?: string;
  extra?: string;
}

export interface FilePrepareResult {
  fileContent: ArrayBuffer | null;
  fileSize: number;
  fileMd5: string;
}

export interface CreateMultiPartResult {
  upload_id: string;
  part_size: number
}


export interface CreateMultiPartBody {
  name: string
  md5: string,
  size: number,
  type: number,
  type_branch?: number,
  encrypt_ver?: string,
}

export interface MultiPartInfo {
  index: number;
  buf: Uint8Array
}

export interface MultiPartCompleteBody {
  md5: string;
  upload_id: string;
}