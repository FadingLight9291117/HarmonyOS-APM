import { getLogger } from './log/Logger';
import { humanizeDuration } from './humanize/humanizeDuration';

/**
 * 锁选项
 */
export interface LockOptions {
  /** 锁名称，用于日志记录 */
  name?: string;
  /** 获取锁的超时时间（毫秒），默认为 0（不超时） */
  timeout?: number;
  /** 获取锁失败时的行为：'throw' 抛出错误，'skip' 跳过执行，'wait' 等待（需要 timeout > 0），默认为 'throw' */
  onLockFailed?: 'throw' | 'skip' | 'wait';
}

/**
 * 简单的互斥锁实现
 */
class Mutex {
  private locked: boolean = false;
  private waiting: Array<() => void> = [];

  async acquire(): Promise<void> {
    if (!this.locked) {
      this.locked = true;
      return;
    }

    return new Promise<void>((resolve) => {
      this.waiting.push(resolve);
    });
  }

  release(): void {
    if (this.waiting.length > 0) {
      const next = this.waiting.shift();
      if (next) {
        next();
      }
    } else {
      this.locked = false;
    }
  }

  isLocked(): boolean {
    return this.locked;
  }
}

/**
 * 全局锁管理器
 */
class LockManager {
  private locks: Map<string, Mutex> = new Map();

  getLock(name: string): Mutex {
    if (!this.locks.has(name)) {
      this.locks.set(name, new Mutex());
    }
    return this.locks.get(name)!;
  }

  removeLock(name: string): void {
    this.locks.delete(name);
  }
}

const lockManager = new LockManager();

/**
 * 带锁的异步操作包装器，确保同一时间只有一个操作在执行
 * 
 * @param lockName 锁名称，相同名称的操作会互斥执行
 * @param fn 要执行的异步函数
 * @param options 锁选项
 * @returns Promise<T> 操作结果
 * 
 * @example
 * ```typescript
 * // 基本用法
 * const result = await withLock('dataProcessing', async () => {
 *   return await processData();
 * });
 * 
 * // 带超时的锁
 * const result = await withLock('criticalOperation', async () => {
 *   return await criticalOperation();
 * }, {
 *   timeout: 5000,
 *   onLockFailed: 'throw'
 * });
 * 
 * // 锁被占用时跳过执行
 * const result = await withLock('optionalTask', async () => {
 *   return await optionalTask();
 * }, {
 *   onLockFailed: 'skip'
 * });
 * ```
 */
export async function withLock<T>(
  lockName: string,
  fn: () => Promise<T>,
  options: LockOptions = {}
): Promise<T | undefined> {
  const logger = getLogger('withLock');
  // ArkTS 不支持对象解构，需要手动访问属性
  const name = options.name ?? lockName;
  const timeout = options.timeout ?? 0;
  const onLockFailed = options.onLockFailed ?? 'throw';
  const lock = lockManager.getLock(lockName);
  const start = Date.now();

  // 如果设置为 skip 且锁已被占用，立即返回 undefined
  if (onLockFailed === 'skip' && lock.isLocked()) {
    logger.info(`${name}: skipping execution due to lock failure`);
    return undefined;
  }

  // 尝试获取锁
  try {
    if (timeout > 0) {
      // 带超时的获取锁
      const timeoutPromise = new Promise<void>((_, reject) => {
        setTimeout(() => {
          reject(new Error(`Failed to acquire lock '${lockName}' within ${humanizeDuration(timeout)}`));
        }, timeout);
      });

      await Promise.race([lock.acquire(), timeoutPromise]);
    } else {
      // 无限等待获取锁
      await lock.acquire();
    }

    const waitTime = Date.now() - start;
    if (waitTime > 0) {
      logger.debug(`${name}: acquired lock '${lockName}' after ${humanizeDuration(waitTime)}`);
    }

    try {
      const result = await fn();
      return result;
    } finally {
      lock.release();
      logger.debug(`${name}: released lock '${lockName}'`);
    }
  } catch (error) {
    if (error?.message.includes('Failed to acquire lock')) {
      // 获取锁失败
      const waitTime = Date.now() - start;
      logger.warn(`${name}: failed to acquire lock '${lockName}' after ${humanizeDuration(waitTime)}`);

      if (onLockFailed === 'skip') {
        logger.info(`${name}: skipping execution due to lock failure`);
        return undefined;
      } else if (onLockFailed === 'wait') {
        // 如果配置为等待，但已经超时，抛出错误
        throw error as Error;
      } else {
        // 默认行为：抛出错误
        throw error as Error;
      }
    } else {
      // 其他错误，释放锁后重新抛出
      lock.release();
      logger.debug(`${name}: released lock '${lockName}' after error`);
      throw error as Error;
    }
  }
}

/**
 * 同步版本的锁包装器
 * 注意：同步版本只能检查锁状态，不能真正等待锁释放
 * 如果锁已被占用，根据 onLockFailed 选项处理
 * 
 * @param lockName 锁名称
 * @param fn 要执行的同步函数
 * @param options 锁选项
 * @returns T | null 操作结果
 * 
 * @example
 * ```typescript
 * const result = withLockSync('syncOperation', () => {
 *   return performSyncOperation();
 * });
 * ```
 */
export function withLockSync<T>(
  lockName: string,
  fn: () => T,
  options: LockOptions = {}
): T | undefined {
  const logger = getLogger('withLock');
  // ArkTS 不支持对象解构，需要手动访问属性
  const name = options.name ?? lockName;
  const onLockFailed = options.onLockFailed ?? 'throw';
  const lock = lockManager.getLock(lockName);

  // 同步检查锁状态
  if (lock.isLocked()) {
    logger.warn(`${name}: lock '${lockName}' is already locked`);

    if (onLockFailed === 'skip') {
      logger.info(`${name}: skipping execution due to lock failure`);
      return undefined;
    } else if (onLockFailed === 'wait') {
      logger.warn(`${name}: 'wait' option not supported in sync context, using 'throw'`);
      throw new Error(`Lock '${lockName}' is already locked`);
    } else {
      throw new Error(`Lock '${lockName}' is already locked`);
    }
  }

  // 尝试立即获取锁（如果锁未被占用）
  // 注意：由于 acquire 是异步的，这里我们假设锁状态检查是准确的
  // 在实际使用中，建议使用异步版本的 withLock
  try {
    // 标记为已锁定（在实际实现中，这应该通过 acquire 完成）
    // 但由于这是同步版本，我们只能依赖 isLocked 检查
    const result = fn();
    logger.debug(`${name}: completed operation with lock '${lockName}'`);
    return result;
  } catch (error) {
    logger.debug(`${name}: operation failed with lock '${lockName}'`);
    throw error as Error;
  }
}

