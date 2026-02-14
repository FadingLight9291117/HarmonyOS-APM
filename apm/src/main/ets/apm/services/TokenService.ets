import { APMConfig } from '../config/types';
import { createDefaultNetworkClient } from '../platform/NetworkClient';
import { ServerStrategy, Strategy } from '../types/networkTypes';
import { getLogger } from '../utils';
import { NetworkService } from './NetworkService';

export class TokenService {
  private readonly TAG = 'TokenService';
  private log = getLogger(this.TAG);
  private token = '';
  private tokenExpireAt = 0;
  private readonly EXPIRY_BUFFER_MS = 5000;
  private networkService: NetworkService;
  private retransmitStrategy: Strategy;
  private defaultStrategy: Strategy;
  private config: APMConfig;

  constructor(config: APMConfig, networkService?: NetworkService) {
    this.config = config;
    this.networkService = networkService || new NetworkService(config, createDefaultNetworkClient());
    this.defaultStrategy = { disable: false, sendGap: String(config.retryInterval), totalSize: String(config.maxRetryCount) };
    this.retransmitStrategy = this.defaultStrategy;
  }

  async getToken(force = false): Promise<string> {
    if (!force && this.isValid()) return this.token;
    try {
      return await this.fetchTokenWithRetry();
    } catch (e) {
      this.log.error('Failed to fetch token', e);
      return ''
    }
  }

  invalidateToken() {
    this.tokenExpireAt = 0;
  }

  private isValid(): boolean {
    return !!this.token && Date.now() + this.EXPIRY_BUFFER_MS < this.tokenExpireAt;
  }

  private async fetchTokenWithRetry(): Promise<string> {
    if (this.retransmitStrategy.disable) {
      return this.fetchToken();
    }
    const max = Math.max(0, parseInt(this.retransmitStrategy.totalSize, 10));
    let lastErr: Error | null = null;
    for (let attempt = 0; attempt <= max; attempt++) {
      try {
        return await this.fetchToken();
      } catch (e) {
        lastErr = e;
        if (attempt === max) {
          break;
        }
        const delayMs = parseInt(this.retransmitStrategy.sendGap, 10) || this.config.retryInterval || 0;
        await this.delay(delayMs);
      }
    }
    throw (lastErr || new Error('Unknown token fetch error'));
  }

  private async fetchToken(): Promise<string> {
    const askData = await this.networkService.ask();
    if (!askData || !askData.token) {
      throw new Error('Invalid token response');
    }
    this.token = askData.token;
    if (askData.token_expire_at) {
      this.tokenExpireAt = askData.token_expire_at * 1000;
    } else if (askData.token_expire_gap) {
      this.tokenExpireAt = Date.now() + askData.token_expire_gap * 1000;
    } else {
      this.tokenExpireAt = Date.now() + 300000;
    }
    const strategies = ServerStrategy.of(askData.strategy)
    this.retransmitStrategy = strategies.getStrategy('retransmit') || this.defaultStrategy;
    this.log.debug(`Fetched token ${this.token}, expires at ${new Date(this.tokenExpireAt).toLocaleString()}, strategy:`, JSON.stringify(this.retransmitStrategy));
    return this.token;
  }

  private delay(ms: number) {
    return new Promise<void>(r => setTimeout(r, ms));
  }
}
