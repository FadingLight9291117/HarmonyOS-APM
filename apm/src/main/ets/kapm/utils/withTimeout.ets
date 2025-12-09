import { getLogger } from './log/Logger';
import { humanizeDuration } from './humanize/humanizeDuration';

export class TimeoutError extends Error {
  public readonly timeout: number;

  constructor(message: string, timeout: number) {
    super(message);
    this.name = 'TimeoutError';
    this.timeout = timeout;
  }
}

/**
 * 带超时控制的异步操作包装器
 * 
 * @param name 操作名称，用于日志记录
 * @param fn 要执行的异步函数
 * @param timeoutMs 超时时间（毫秒）
 * @returns Promise<T> 操作结果
 * 
 * @example
 * ```typescript
 * // 基本用法
 * const result = await withTimeout('fetchData', async () => {
 *   return await fetchDataFromServer();
 * }, 5000); // 5秒超时
 * 
 * // 处理超时错误
 * try {
 *   const result = await withTimeout('slowOperation', async () => {
 *     return await slowOperation();
 *   }, 3000);
 * } catch (error) {
 *   if (error instanceof TimeoutError) {
 *     console.log('操作超时了');
 *   }
 * }
 * ```
 */
export async function withTimeout<T>(
  name: string,
  fn: () => Promise<T>,
  timeoutMs: number
): Promise<T> {
  const logger = getLogger('withTimeout');
  const start = Date.now();

  return new Promise<T>((resolve, reject) => {
    // 设置超时定时器
    const timeoutId = setTimeout(() => {
      const elapsed = Date.now() - start;
      const error = new TimeoutError(
        `${name} timed out after ${humanizeDuration(timeoutMs)} (elapsed: ${humanizeDuration(elapsed)})`,
        timeoutMs
      );
      logger.error(`${name}: timeout after ${humanizeDuration(timeoutMs)}`);
      reject(error);
    }, timeoutMs);

    // 执行操作
    fn()
      .then((result) => {
        clearTimeout(timeoutId);
        const elapsed = Date.now() - start;
        logger.debug(`${name} completed in ${humanizeDuration(elapsed)} (timeout: ${humanizeDuration(timeoutMs)})`);
        resolve(result);
      })
      .catch((error: Error) => {
        clearTimeout(timeoutId);
        const elapsed = Date.now() - start;
        logger.error(`${name} failed after ${humanizeDuration(elapsed)} (timeout: ${humanizeDuration(timeoutMs)}):`, error.message);
        reject(error);
      });
  });
}

