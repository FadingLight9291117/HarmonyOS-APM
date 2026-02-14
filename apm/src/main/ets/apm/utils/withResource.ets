import { getLogger } from './log/Logger';

/**
 * 资源类型，必须包含清理方法
 */
export interface Resource {
  /** 清理资源的方法 */
  dispose: () =>  void | Promise<void>;
}

/**
 * 资源管理选项
 */
export interface ResourceOptions {
  /** 资源名称，用于日志记录 */
  name?: string;

  /** 是否在出错时也执行清理，默认为 true */
  cleanupOnError?: boolean;
}

/**
 * 带资源管理的操作包装器，确保资源在使用后自动清理
 *
 * @param resource 资源对象，必须实现 dispose 方法
 * @param fn 使用资源的操作函数
 * @param options 资源管理选项
 * @returns Promise<T> 操作结果
 *
 * @example
* ```typescript
 * // 文件资源
 * const result = await withResource(
 *   { dispose: () => fileIo.close(file) },
 *   async (resource) => {
 *     return await readFile(file);
 *   }
 * );
 *
 * // 自定义资源类
 * class DatabaseConnection implements Resource {
 *   dispose() {
 *     this.connection.close();
 *   }
 * }
 *
 * const db = new DatabaseConnection();
 * const result = await withResource(db, async () => {
 *   return await db.query('SELECT * FROM users');
 * });
 * ```
 */
export async function withResource<T, R extends Resource>(
  resource: R,
  fn: (resource: R) => Promise<T>,
  options: ResourceOptions = {}
): Promise<T> {
  const logger = getLogger('withResource');
  // ArkTS 不支持对象解构，需要手动访问属性
  const name = options.name ?? 'resource';
  const cleanupOnError = options.cleanupOnError ?? true;

  try {
    const result = await fn(resource);

    // 正常执行后清理资源
    try {
      await Promise.resolve(resource.dispose());
      logger.debug(`${name}: resource disposed successfully`);
    } catch (cleanupError) {
      logger.error(`${name}: error disposing resource:`, cleanupError);
    }

    return result;
  } catch (error) {
    // 如果启用错误时清理，则执行清理
    if (cleanupOnError) {
      try {
        await Promise.resolve(resource.dispose());
        logger.debug(`${name}: resource disposed after error`);
      } catch (cleanupError) {
        logger.error(`${name}: error disposing resource after failure:`, cleanupError);
      }
    }
    throw error as Error;
  }
}

/**
 * 同步版本的资源管理包装器
 *
 * @param resource 资源对象，必须实现 dispose 方法
 * @param fn 使用资源的操作函数
 * @param options 资源管理选项
 * @returns T 操作结果
 *
 * @example
* ```typescript
 * const result = withResourceSync(
 *   { dispose: () => lock.release() },
 *   (resource) => {
 *     return performOperation();
 *   }
 * );
 * ```
 */
export function withResourceSync<T, R extends Resource>(
  resource: R,
  fn: (resource: R) => T,
  options: ResourceOptions = {}
): T {
  const logger = getLogger('withResource');
  // ArkTS 不支持对象解构，需要手动访问属性
  const name = options.name ?? 'resource';
  const cleanupOnError = options.cleanupOnError ?? true;

  try {
    const result = fn(resource);

    // 正常执行后清理资源
    try {
      const disposeResult = resource.dispose();
      if (disposeResult instanceof Promise) {
        // 如果是异步清理，记录警告但不等待
        logger.warn(`${name}: resource.dispose() returned Promise in sync context, consider using withResource instead`);
        disposeResult.catch((err: Error): void => logger.error(`${name}: async dispose error:`, err.message));
      } else {
        logger.debug(`${name}: resource disposed successfully`);
      }
    } catch (cleanupError) {
      logger.error(`${name}: error disposing resource:`, cleanupError);
    }

    return result;
  } catch (error) {
    // 如果启用错误时清理，则执行清理
    if (cleanupOnError) {
      try {
        const disposeResult = resource.dispose();
        if (disposeResult instanceof Promise) {
          logger.warn(`${name}: resource.dispose() returned Promise in sync context`);
          disposeResult.catch((err: Error): void => logger.error(`${name}: async dispose error:`, err.message));
        } else {
          logger.debug(`${name}: resource disposed after error`);
        }
      } catch (cleanupError) {
        logger.error(`${name}: error disposing resource after failure:`, cleanupError);
      }
    }
    throw error as Error;
  }
}

