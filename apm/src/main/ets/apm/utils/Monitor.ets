export interface BasicMetrics {
  reportTotal: number;
  reportSuccess: number;
  reportFailed: number;
  cacheOperations: number;
  tokenRefreshCount: number;
}

export enum MetricKeys {
  ReportTotal = 'reportTotal',
  ReportSuccess = 'reportSuccess',
  ReportFailed = 'reportFailed',
  CacheOperations = 'cacheOperations',
  TokenRefreshCount = 'tokenRefreshCount'
}

export class Monitor {
  private metrics: Record<string, number> = {
    'reportTotal': 0,
    'reportSuccess': 0,
    'reportFailed': 0,
    'cacheOperations': 0,
    'tokenRefreshCount': 0
  };

  inc<K extends keyof BasicMetrics>(key: MetricKeys | K) { this.metrics[key]++; }
  // Return a shallow copy without spread operator
  get(): BasicMetrics {
    // 手动浅拷贝，避免 Object.assign
    const copy: BasicMetrics = {
      reportTotal: this.metrics.reportTotal,
      reportSuccess: this.metrics.reportSuccess,
      reportFailed: this.metrics.reportFailed,
      cacheOperations: this.metrics.cacheOperations,
      tokenRefreshCount: this.metrics.tokenRefreshCount,
    };
    return copy;
  }
}
