import { humanizeDuration } from './humanize/humanizeDuration';
import { getLogger } from './log/Logger';
import { taskpool } from '@kit.ArkTS';

/**
 * 在后台线程中执行任务并记录执行时间
 *
 * @param name 任务名称，用于日志记录
 * @param fn 要执行的任务函数（必须是可序列化的）
 * @returns Promise<T> 任务执行结果
 *
 * @example
* ```typescript
 * const result = await withTask('processData', () => {
 *   // 在后台线程执行的代码
 *   return processLargeData();
 * });
 * ```
 */
export async function withTask<T>(name: string, fn: () => T): Promise<T> {
  const logger = getLogger('withTask');
  const start = Date.now();
  try {
    const task = new taskpool.Task(fn);
    const res = await taskpool.execute(task);
    const end = Date.now();
    logger.info(`Task ${name} completed in ${humanizeDuration(end - start)}`);
    return res as T;
  } catch (error) {
    const end = Date.now();
    logger.error(`Task ${name} failed after ${humanizeDuration(end - start)}:`, error);
    throw error as Error;
  }
}



@Concurrent
function foo() {
  console.log('test withTask');
}

withTask('', foo)