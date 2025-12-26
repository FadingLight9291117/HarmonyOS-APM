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
  private waiting: Array<Waiter> = [];

  tryAcquire(): boolean {
    if (this.locked) {
      return false;
    }
    this.locked = true;
    return true;
  }

  async acquire(timeoutMs: number = 0, lockNameForError: string = 'lock'): Promise<void> {
    if (this.tryAcquire()) {
      return;
    }

    return new Promise<void>((resolve, reject) => {
      const waiter: Waiter = { resolve, reject, canceled: false };

      if (timeoutMs > 0) {
        waiter.timerId = setTimeout(() => {
          waiter.canceled = true;
          // 从等待队列中移除，避免超时后仍被 release() 唤醒导致“幽灵持锁者”
          const idx = this.waiting.indexOf(waiter);
          if (idx >= 0) {
            this.waiting.splice(idx, 1);
          }
          reject(new LockTimeoutError(lockNameForError, timeoutMs));
        }, timeoutMs);
      }

      this.waiting.push(waiter);
    });
  }

  release(): void {
    // 释放时：优先唤醒一个未取消的等待者；如果都被取消了，则真正释放锁
    while (this.waiting.length > 0) {
      const next = this.waiting.shift();
      if (!next) continue;
      if (next.canceled) continue;
      if (next.timerId) {
        clearTimeout(next.timerId);
      }
      // 这里不需要设置 locked = true：锁仍然保持占用状态，所有权转交给被唤醒者
      next.resolve();
      return;
    }

    this.locked = false;
  }

  isLocked(): boolean {
    return this.locked;
  }
}

interface Waiter {
  resolve: () => void;
  reject: (err: Error) => void;
  canceled: boolean;
  timerId?: number;
};

export class LockTimeoutError extends Error {
  public readonly lockName: string;
  public readonly timeoutMs: number;

  constructor(lockName: string, timeoutMs: number) {
    super(`Failed to acquire lock '${lockName}' within ${humanizeDuration(timeoutMs)}`);
    this.name = 'LockTimeoutError';
    this.lockName = lockName;
    this.timeoutMs = timeoutMs;
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
    logger.debug(`${name}: skipping execution due to lock failure`);
    return undefined;
  }

  // 尝试获取锁
  try {
    await lock.acquire(timeout, lockName);

    const waitTime = Date.now() - start;
    if (waitTime > 0) {
      logger.debug(`${name}: acquired lock '${lockName}' after ${humanizeDuration(waitTime)}`);
    }

    try {
      const result = await fn();
      logger.debug(`${name}: completed operation with lock '${lockName}'`);
      return result;
    } finally {
      lock.release();
      logger.debug(`${name}: released lock '${lockName}'`);
    }
  } catch (error) {
    if (error instanceof LockTimeoutError) {
      // 获取锁失败
      const waitTime = Date.now() - start;
      logger.warn(`${name}: failed to acquire lock '${lockName}' after ${humanizeDuration(waitTime)}`);

      if (onLockFailed === 'skip') {
        logger.debug(`${name}: skipping execution due to lock failure`);
        return undefined;
      } else if (onLockFailed === 'wait') {
        // 如果配置为等待，但设置了 timeout 仍然会超时：抛出错误交给上层决定
        throw error;
      } else {
        // 默认行为：抛出错误
        throw error;
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

  // 同步场景下尝试立即获取锁（不等待）
  if (!lock.tryAcquire()) {
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

  try {
    const result = fn();
    logger.debug(`${name}: completed operation with lock '${lockName}'`);
    return result;
  } catch (error) {
    logger.warn(`${name}: operation failed with lock '${lockName}'`);
    throw error as Error;
  } finally {
    lock.release();
    logger.debug(`${name}: released lock '${lockName}' (sync)`);
  }
}

