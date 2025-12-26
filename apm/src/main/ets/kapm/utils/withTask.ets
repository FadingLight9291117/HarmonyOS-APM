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


const longTaskMap = new Map<string, taskpool.LongTask>();

export async function withLongTask<T, A extends object[]>(name: string, fn: (...args: A) => T, ...args: A): Promise<T> {
  const logger = getLogger('withLongTask');
  const start = Date.now();
  try {
    const task = new taskpool.LongTask(fn, ...args);
    longTaskMap.set(name, task);
    const res = await taskpool.execute(task);
    const end = Date.now();
    logger.info(`Long Task ${name} completed in ${humanizeDuration(end - start)}`);
    return res as T;
  } catch (error) {
    const end = Date.now();
    logger.error(`Long Task ${name} failed after ${humanizeDuration(end - start)}:`, error.message);
    throw error as Error;
  }
}

export function stopLongTask(name: string): void {
  const logger = getLogger('withLongTask');
  try {
    const task = longTaskMap.get(name);
    if (!task) {
      logger.warn(`No long task found with name ${name}`);
      return;
    }
    taskpool.terminateTask(task);
    logger.info(`All tasks including ${name} have been stopped.`);
  } catch (error) {
    logger.error(`Failed to stop tasks including ${name}:`, error);
    throw error as Error;
  }
}
