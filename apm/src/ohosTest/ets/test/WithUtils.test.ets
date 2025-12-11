import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import {
  withTimeout,
  TimeoutError,
  withTiming,
  withRetry,
  withResource,
  withResourceSync,
  withLock,
  withLockSync,
  Resource
} from '../../../main/ets/kapm/utils';
import { withTimingSync } from '../../../main/ets/kapm/utils/withTiming';

export default function withUtilsTest() {
  describe('WithUtilsTest', () => {
    beforeAll(() => {
      // 测试套件初始化
    });

    beforeEach(() => {
      // 每个测试用例前的准备
    });

    afterEach(() => {
      // 每个测试用例后的清理
    });

    afterAll(() => {
      // 测试套件结束后的清理
    });

    describe('withTimeout', () => {
      it('should return result when operation completes before timeout', 0, async () => {
        const result = await withTimeout('test', async () => {
          return 'success';
        }, 1000);
        expect(result).assertEqual('success');
      });

      it('should throw TimeoutError when operation exceeds timeout', 0, async () => {
        try {
          await withTimeout('slow', async () => {
            await new Promise<void>(resolve => setTimeout(resolve, 200));
            return 'done';
          }, 50);
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof TimeoutError).assertTrue();
          if (error instanceof TimeoutError) {
            expect(error.timeout).assertEqual(50);
            expect(error.message).assertContain('timed out');
          }
        }
      });

      it('should propagate errors from operation', 0, async () => {
        try {
          await withTimeout('error', async () => {
            throw new Error('operation error');
          }, 1000);
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertEqual('operation error');
          }
        }
      });

      it('should handle fast operations', 0, async () => {
        const result = await withTimeout('fast', async () => {
          return 42;
        }, 1000);
        expect(result).assertEqual(42);
      });
    });

    describe('withTiming', () => {
      it('should return result from async operation', 0, async () => {
        const result = await withTiming('test', async () => {
          return 'success';
        });
        expect(result).assertEqual('success');
      });

      it('should propagate errors from async operation', 0, async () => {
        try {
          await withTiming('error', async () => {
            throw new Error('test error');
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertEqual('test error');
          }
        }
      });

      it('should handle async operations with delay', 0, async () => {
        const start = Date.now();
        const result = await withTiming('delayed', async () => {
          await new Promise<void>(resolve => setTimeout(resolve, 10));
          return 'delayed result';
        });
        const elapsed = Date.now() - start;
        expect(result).assertEqual('delayed result');
        expect(elapsed).assertLargerOrEqual(10);
      });
    });

    describe('withTimingSync', () => {
      it('should return result from sync operation', 0, () => {
        const result = withTimingSync('test', () => {
          return 'success';
        });
        expect(result).assertEqual('success');
      });

      it('should propagate errors from sync operation', 0, () => {
        try {
          withTimingSync('error', () => {
            throw new Error('sync error');
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertEqual('sync error');
          }
        }
      });

      it('should handle sync operations with computation', 0, () => {
        const result = withTimingSync('compute', () => {
          let sum = 0;
          for (let i = 0; i < 100; i++) {
            sum += i;
          }
          return sum;
        });
        expect(result).assertEqual(4950);
      });
    });

    describe('withRetry', () => {
      it('should return result on first attempt', 0, async () => {
        const result = await withRetry('test', async () => {
          return 'success';
        });
        expect(result).assertEqual('success');
      });

      it('should retry on failure and succeed', 0, async () => {
        let attempts = 0;
        const result = await withRetry('retry', async () => {
          attempts++;
          if (attempts < 2) {
            throw new Error('temporary error');
          }
          return 'success after retry';
        }, {
          maxRetries: 3,
          retryInterval: 10
        });
        expect(result).assertEqual('success after retry');
        expect(attempts).assertEqual(2);
      });

      it('should throw error after max retries', 0, async () => {
        let attempts = 0;
        try {
          await withRetry('fail', async () => {
            attempts++;
            throw new Error('always fails');
          }, {
            maxRetries: 2,
            retryInterval: 10
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertEqual('always fails');
          }
          expect(attempts).assertEqual(3); // 1 initial + 2 retries
        }
      });

      it('should use exponential backoff', 0, async () => {
        const delays: number[] = [];
        let lastTime = Date.now();

        try {
          await withRetry('backoff', async () => {
            const now = Date.now();
            if (delays.length > 0) {
              delays.push(now - lastTime);
            }
            lastTime = now;
            throw new Error('fail');
          }, {
            maxRetries: 2,
            retryInterval: 10,
            exponentialBackoff: true,
            backoffMultiplier: 2
          });
        } catch (error) {
          // 忽略错误，只检查延迟
        }

        // 验证延迟时间（允许一些误差）
        if (delays.length >= 1) {
          expect(delays[0]).assertLargerOrEqual(10);
        }
      });

      it('should respect shouldRetry callback', 0, async () => {
        let attempts = 0;
        try {
          await withRetry('shouldRetry', async () => {
            attempts++;
            throw new Error('network error');
          }, {
            maxRetries: 3,
            retryInterval: 10,
            shouldRetry: (error: Error) => {
              return error.message.includes('network');
            }
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          expect(attempts).assertLargerOrEqual(2);
        }
      });

      it('should not retry when shouldRetry returns false', 0, async () => {
        let attempts = 0;
        try {
          await withRetry('noRetry', async () => {
            attempts++;
            throw new Error('fatal error');
          }, {
            maxRetries: 3,
            retryInterval: 10,
            shouldRetry: (error: Error) => {
              return false; // 不重试
            }
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          expect(attempts).assertEqual(1); // 只尝试一次
        }
      });

      it('should call onRetry callback', 0, async () => {
        let retryCalled = false;
        let attempts = 0;

        await withRetry('onRetry', async () => {
          attempts++;
          if (attempts < 2) {
            throw new Error('retry');
          }
          return 'success';
        }, {
          maxRetries: 2,
          retryInterval: 10,
          onRetry: (error: Error, attempt: number) => {
            retryCalled = true;
            expect(attempt).assertLargerOrEqual(1);
          }
        });

        expect(retryCalled).assertTrue();
      });

      it('should handle maxRetries = 0', 0, async () => {
        let attempts = 0;
        try {
          await withRetry('zeroRetries', async () => {
            attempts++;
            throw new Error('error');
          }, {
            maxRetries: 0,
            retryInterval: 10
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          expect(attempts).assertEqual(1); // 只尝试一次
        }
      });

      it('should handle custom backoffMultiplier', 0, async () => {
        const delays: number[] = [];
        let lastTime = Date.now();

        try {
          await withRetry('customBackoff', async () => {
            const now = Date.now();
            if (delays.length > 0) {
              delays.push(now - lastTime);
            }
            lastTime = now;
            throw new Error('fail');
          }, {
            maxRetries: 2,
            retryInterval: 10,
            exponentialBackoff: true,
            backoffMultiplier: 3
          });
        } catch (error) {
          // 忽略错误，只检查延迟
        }

        // 验证延迟时间（允许一些误差）
        if (delays.length >= 1) {
          expect(delays[0]).assertLargerOrEqual(10);
        }
      });
    });

    describe('withResource', () => {
      it('should dispose resource after successful operation', 0, async () => {
        let disposed = false;
        const resource: Resource = {
          dispose: () => {
            disposed = true;
          }
        };

        const result = await withResource(resource, async () => {
          return 'success';
        });

        expect(result).assertEqual('success');
        expect(disposed).assertTrue();
      });

      it('should dispose resource on error when cleanupOnError is true', 0, async () => {
        let disposed = false;
        const resource: Resource = {
          dispose: () => {
            disposed = true;
          }
        };

        try {
          await withResource(resource, async () => {
            throw new Error('operation error');
          }, {
            cleanupOnError: true
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          expect(disposed).assertTrue();
        }
      });

      it('should not dispose resource on error when cleanupOnError is false', 0, async () => {
        let disposed = false;
        const resource: Resource = {
          dispose: () => {
            disposed = true;
          }
        };

        try {
          await withResource(resource, async () => {
            throw new Error('operation error');
          }, {
            cleanupOnError: false
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          expect(disposed).assertFalse();
        }
      });

      it('should handle async dispose', 0, async () => {
        let disposed = false;
        const resource: Resource = {
          dispose: async () => {
            await new Promise<void>(resolve => setTimeout(resolve, 10));
            disposed = true;
          }
        };

        const result = await withResource(resource, async () => {
          return 'success';
        });

        expect(result).assertEqual('success');
        // 等待异步 dispose 完成
        await new Promise<void>(resolve => setTimeout(resolve, 20));
        expect(disposed).assertTrue();
      });

      it('should propagate errors from operation', 0, async () => {
        const resource: Resource = {
          dispose: () => {
          }
        };

        try {
          await withResource(resource, async () => {
            throw new Error('operation error');
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertEqual('operation error');
          }
        }
      });

      it('should handle dispose throwing error', 0, async () => {
        const resource: Resource = {
          dispose: () => {
            throw new Error('dispose error');
          }
        };

        // dispose 抛出错误不应该影响操作结果
        const result = await withResource(resource, async () => {
          return 'success';
        });
        expect(result).assertEqual('success');
      });

      it('should use custom name option', 0, async () => {
        let disposed = false;
        const resource: Resource = {
          dispose: () => {
            disposed = true;
          }
        };

        const result = await withResource(resource, async () => {
          return 'success';
        }, {
          name: 'custom-resource'
        });

        expect(result).assertEqual('success');
        expect(disposed).assertTrue();
      });
    });

    describe('withResourceSync', () => {
      it('should dispose resource after successful operation', 0, () => {
        let disposed = false;
        const resource: Resource = {
          dispose: () => {
            disposed = true;
          }
        };

        const result = withResourceSync(resource, () => {
          return 'success';
        });

        expect(result).assertEqual('success');
        expect(disposed).assertTrue();
      });

      it('should dispose resource on error when cleanupOnError is true', 0, () => {
        let disposed = false;
        const resource: Resource = {
          dispose: () => {
            disposed = true;
          }
        };

        try {
          withResourceSync(resource, () => {
            throw new Error('operation error');
          }, {
            cleanupOnError: true
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          expect(disposed).assertTrue();
        }
      });

      it('should handle async dispose in sync context', 0, () => {
        let disposed = false;
        const resource: Resource = {
          dispose: async () => {
            await new Promise<void>(resolve => setTimeout(resolve, 10));
            disposed = true;
          }
        };

        const result = withResourceSync(resource, () => {
          return 'success';
        });

        expect(result).assertEqual('success');
        // 注意：在同步上下文中，异步 dispose 会被记录警告但不等待
      });

      it('should propagate errors from operation', 0, () => {
        const resource: Resource = {
          dispose: () => {
          }
        };

        try {
          withResourceSync(resource, () => {
            throw new Error('sync error');
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertEqual('sync error');
          }
        }
      });

      it('should handle dispose throwing error', 0, () => {
        const resource: Resource = {
          dispose: () => {
            throw new Error('dispose error');
          }
        };

        // dispose 抛出错误不应该影响操作结果
        const result = withResourceSync(resource, () => {
          return 'success';
        });
        expect(result).assertEqual('success');
      });
    });

    describe('withLock', () => {
      it('should execute operation when lock is available', 0, async () => {
        const result = await withLock('test-lock', async () => {
          return 'success';
        });
        expect(result).assertEqual('success');
      });

      it('should serialize concurrent operations with same lock', 0, async () => {
        const results: string[] = [];

        const promise1 = withLock('serial-lock', async () => {
          await new Promise<void>(resolve => setTimeout(resolve, 50));
          results.push('first');
          return 'first';
        });

        const promise2 = withLock('serial-lock', async () => {
          results.push('second');
          return 'second';
        });

        const GeneratedDestructArray_1 = await Promise.all([promise1, promise2]);
        const result1 = GeneratedDestructArray_1[0];
        const result2 = GeneratedDestructArray_1[1];

        expect(result1).assertEqual('first');
        expect(result2).assertEqual('second');
        expect(results[0]).assertEqual('first');
        expect(results[1]).assertEqual('second');
      });

      it('should allow concurrent operations with different locks', 0, async () => {
        const results: string[] = [];

        const promise1 = withLock('lock1', async () => {
          await new Promise<void>(resolve => setTimeout(resolve, 30));
          results.push('lock1');
          return 'lock1';
        });

        const promise2 = withLock('lock2', async () => {
          results.push('lock2');
          return 'lock2';
        });

        const GeneratedDestructArray_2 = await Promise.all([promise1, promise2]);
        const result1 = GeneratedDestructArray_2[0];
        const result2 = GeneratedDestructArray_2[1];

        expect(result1).assertEqual('lock1');
        expect(result2).assertEqual('lock2');
        // lock2 应该先完成，因为使用不同的锁
        expect(results[0]).assertEqual('lock2');
        expect(results[1]).assertEqual('lock1');
      });

      it('should skip operation when onLockFailed is skip', 0, async () => {
        // 先获取锁
        const lockPromise = withLock('skip-lock', async () => {
          await new Promise<void>(resolve => setTimeout(resolve, 100));
          return 'locked';
        });

        // 立即尝试获取同一个锁，应该跳过
        const skipResult = await withLock('skip-lock', async () => {
          return 'should not execute';
        }, {
          onLockFailed: 'skip'
        });

        expect(skipResult).assertUndefined();

        // 等待第一个操作完成
        const lockResult = await lockPromise;
        expect(lockResult).assertEqual('locked');
      });

      it('should throw error when onLockFailed is throw and timeout', 0, async () => {
        // 先获取锁
        const lockPromise = withLock('throw-lock', async () => {
          await new Promise<void>(resolve => setTimeout(resolve, 100));
          return 'locked';
        });

        // 立即尝试获取同一个锁，应该超时并抛出错误
        try {
          await withLock('throw-lock', async () => {
            return 'should not execute';
          }, {
            timeout: 10,
            onLockFailed: 'throw'
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertContain('Failed to acquire lock');
          }
        }

        // 等待第一个操作完成
        await lockPromise;
      });

      it('should propagate errors from operation', 0, async () => {
        try {
          await withLock('error-lock', async () => {
            throw new Error('operation error');
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertEqual('operation error');
          }
        }
      });

      it('should handle onLockFailed wait option with timeout', 0, async () => {
        // 先获取锁
        const lockPromise = withLock('wait-lock', async () => {
          await new Promise<void>(resolve => setTimeout(resolve, 50));
          return 'locked';
        });

        // 立即尝试获取同一个锁，应该超时并抛出错误（wait 在超时后也会抛出错误）
        try {
          await withLock('wait-lock', async () => {
            return 'should not execute';
          }, {
            timeout: 10,
            onLockFailed: 'wait'
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertContain('Failed to acquire lock');
          }
        }

        // 等待第一个操作完成
        await lockPromise;
      });

      it('should use custom name option', 0, async () => {
        const result = await withLock('name-lock', async () => {
          return 'success';
        }, {
          name: 'custom-name'
        });
        expect(result).assertEqual('success');
      });
    });

    describe('withLockSync', () => {
      it('should execute operation when lock is available', 0, () => {
        const result = withLockSync('sync-test-lock', () => {
          return 'success';
        });
        expect(result).assertEqual('success');
      });

      it('should skip operation when onLockFailed is skip', 0, () => {
        // 先获取锁（使用异步版本）
        const lockPromise = withLock('sync-skip-lock', async () => {
          await new Promise<void>(resolve => setTimeout(resolve, 100));
          return 'locked';
        });

        // 立即尝试获取同一个锁，应该跳过
        const skipResult = withLockSync('sync-skip-lock', () => {
          return 'should not execute';
        }, {
          onLockFailed: 'skip'
        });

        expect(skipResult).assertUndefined();

        // 等待第一个操作完成
        lockPromise.then(() => {
          // 清理
        });
      });

      it('should throw error when onLockFailed is throw', 0, () => {
        // 先获取锁（使用异步版本）
        const lockPromise = withLock('sync-throw-lock', async () => {
          await new Promise<void>(resolve => setTimeout(resolve, 100));
          return 'locked';
        });

        // 立即尝试获取同一个锁，应该抛出错误
        try {
          withLockSync('sync-throw-lock', () => {
            return 'should not execute';
          }, {
            onLockFailed: 'throw'
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertContain('already locked');
          }
        }

        // 等待第一个操作完成
        lockPromise.then(() => {
          // 清理
        });
      });

      it('should throw error when onLockFailed is wait', 0, () => {
        // 先获取锁（使用异步版本）
        const lockPromise = withLock('sync-wait-lock', async () => {
          await new Promise<void>(resolve => setTimeout(resolve, 100));
          return 'locked';
        });

        // 立即尝试获取同一个锁，应该抛出错误（wait 在同步上下文中不支持）
        try {
          withLockSync('sync-wait-lock', () => {
            return 'should not execute';
          }, {
            onLockFailed: 'wait'
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertContain('already locked');
          }
        }

        // 等待第一个操作完成
        lockPromise.then(() => {
          // 清理
        });
      });

      it('should propagate errors from operation', 0, () => {
        try {
          withLockSync('sync-error-lock', () => {
            throw new Error('operation error');
          });
          expect(true).assertFalse(); // 不应该执行到这里
        } catch (error) {
          expect(error instanceof Error).assertTrue();
          if (error instanceof Error) {
            expect(error.message).assertEqual('operation error');
          }
        }
      });

      it('should use custom name option', 0, () => {
        const result = withLockSync('sync-name-lock', () => {
          return 'success';
        }, {
          name: 'custom-sync-name'
        });
        expect(result).assertEqual('success');
      });
    });
  });
}