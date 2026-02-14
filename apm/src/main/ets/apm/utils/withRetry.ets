import { getLogger } from './log/Logger';

export interface RetryOptions {
  /** 最大重试次数（不包括首次尝试），默认为 3 */
  maxRetries?: number;
  /** 重试间隔（毫秒），默认为 1000 */
  retryInterval?: number;
  /** 是否启用指数退避，默认为 false */
  exponentialBackoff?: boolean;
  /** 指数退避的基础倍数，默认为 2 */
  backoffMultiplier?: number;
  /** 自定义错误处理函数，返回 true 表示应该重试，false 表示不应该重试 */
  shouldRetry?: (error: Error, attempt: number) => boolean;
  /** 重试前的回调函数 */
  onRetry?: (error: Error, attempt: number) => void;
}

/**
 * 带重试机制的异步操作包装器
 * 
 * @param name 操作名称，用于日志记录
 * @param fn 要执行的异步函数
 * @param options 重试配置选项
 * @returns Promise<T> 操作结果
 * 
 * @example
 * ```typescript
 * // 基本用法
 * const result = await withRetry('fetchData', async () => {
 *   return await fetchDataFromServer();
 * });
 * 
 * // 自定义重试配置
 * const result = await withRetry('uploadFile', async () => {
 *   return await uploadFile(file);
 * }, {
 *   maxRetries: 5,
 *   retryInterval: 2000,
 *   exponentialBackoff: true,
 *   shouldRetry: (error, attempt) => {
 *     // 只对网络错误重试
 *     return error.message.includes('network');
 *   }
 * });
 * ```
 */
export async function withRetry<T>(
  name: string,
  fn: () => Promise<T>,
  options: RetryOptions = {}
): Promise<T> {
  const logger = getLogger('withRetry');
  // ArkTS 不支持对象解构，需要手动访问属性
  const maxRetries = options.maxRetries ?? 3;
  const retryInterval = options.retryInterval ?? 1000;
  const exponentialBackoff = options.exponentialBackoff ?? false;
  const backoffMultiplier = options.backoffMultiplier ?? 2;
  const shouldRetry = options.shouldRetry;
  const onRetry = options.onRetry;

  const maxAttempts = maxRetries + 1;
  let lastError: Error;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      if (attempt > 1) {
        logger.debug(`${name}: retry attempt ${attempt}/${maxAttempts}`);
      }
      const result = await fn();
      
      if (attempt > 1) {
        logger.info(`${name}: succeeded on retry attempt ${attempt - 1}`);
      }
      return result;
    } catch (error) {
      lastError = error as Error;
      
      // 检查是否应该重试
      if (shouldRetry && !shouldRetry(lastError, attempt)) {
        logger.warn(`${name}: error should not be retried`, lastError.message);
        throw lastError;
      }

      // 如果是最后一次尝试，不再重试
      if (attempt >= maxAttempts) {
        logger.error(`${name}: all ${maxAttempts} attempts failed`, lastError.message);
        throw lastError;
      }

      // 调用重试回调
      if (onRetry) {
        onRetry(lastError, attempt);
      }

      // 计算延迟时间
      let delay = retryInterval;
      if (exponentialBackoff) {
        delay = retryInterval * Math.pow(backoffMultiplier, attempt - 1);
      }

      logger.warn(`${name}: attempt ${attempt} failed, retrying in ${delay}ms`, lastError.message);
      await delayMs(delay);
    }
  }

  throw lastError!;
}

function delayMs(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

