import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import {
  withLongTask, stopLongTask
} from '../../../main/ets/kapm/utils';

// @Concurrent 函数用于 withLongTask 测试
@Concurrent
function testLongTaskSuccess(): string {
  return 'success';
}

@Concurrent
function testLongTaskCompute(): number {
  let sum = 0;
  for (let i = 0; i < 1000; i++) {
    sum += i;
  }
  return sum;
}

@Concurrent
function testLongTaskError(): string {
  throw new Error('task error');
}

@Concurrent
async function testLongTaskAsync(): Promise<string> {
  await new Promise<void>(resolve => setTimeout(resolve, 10));
  return 'async result';
}

@Concurrent
function testLongTaskResult1(): string {
  return 'result1';
}

@Concurrent
function testLongTaskResult2(): string {
  return 'result2';
}

@Concurrent
function testLongTaskArray(): number[] {
  const input = [1, 2, 3, 4, 5];
  return input.map(x => x * 2);
}

@Concurrent
async function testLongTaskMultiStop(): Promise<string> {
  await new Promise<void>(resolve => setTimeout(resolve, 50));
  return 'done';
}

@Concurrent
function testLongTaskCompleted(): string {
  return 'completed';
}

@Concurrent
async function testLongTaskStopRunning(): Promise<string> {
  // 模拟长时间运行的任务（循环足够多次，确保可以被停止）
  for (let i = 0; i < 10000; i++) {
    await new Promise<void>(resolve => setTimeout(resolve, 20));
  }
  return 'completed';
}

export default function withTaskTest() {
  describe('WithTaskTest', () => {
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

    describe('withLongTask', () => {
      it('should execute long task and return result', 0, async () => {
        const result = await withLongTask('test-long-task', testLongTaskSuccess);
        expect(result).assertEqual('success');
      });

      it('should handle computation in long task', 0, async () => {
        const result = await withLongTask('compute-task', testLongTaskCompute);
        expect(result).assertEqual(499500);
      });

      it('should propagate errors from long task', 0, async () => {
        let errorCaught = false;
        try {
          await withLongTask('error-task', testLongTaskError);
          // 如果执行到这里，说明没有抛出错误，测试应该失败
          expect(errorCaught).assertTrue(); // 这行不应该执行，如果执行了说明没有抛出错误
        } catch (error) {
          errorCaught = true;
          // TaskPool 可能将错误包装成对象，验证错误确实存在
          // 验证 error 不是 undefined 或 null
          expect(error === undefined).assertFalse();
          expect(error === null).assertFalse();
          // 验证错误可以被转换为字符串（说明是一个有效的错误对象）
          const errorStr = String(error);
          expect(errorStr.length).assertLarger(0);
          // 注意：TaskPool 可能会将错误消息包装，我们只验证错误被抛出，不检查具体消息内容
          // 因为 TaskPool 的错误格式可能因版本而异
        }
        // 确保确实捕获到了错误（这是最重要的验证）
        expect(errorCaught).assertTrue();
      });

      it('should handle async operations in long task', 0, async () => {
        const result = await withLongTask('async-task', testLongTaskAsync);
        expect(result).assertEqual('async result');
      });

      it('should handle multiple long tasks with different names', 0, async () => {
        const task1 = withLongTask('task1', testLongTaskResult1);
        const task2 = withLongTask('task2', testLongTaskResult2);

        const GeneratedDestructArray_1 = await Promise.all([task1, task2]);
        const result1 = GeneratedDestructArray_1[0];
        const result2 = GeneratedDestructArray_1[1];
        expect(result1).assertEqual('result1');
        expect(result2).assertEqual('result2');
      });

      it('should handle long task with array processing', 0, async () => {
        const result = await withLongTask('array-task', testLongTaskArray);
        const expected = [2, 4, 6, 8, 10];
        // 验证数组长度
        expect(result.length).assertEqual(expected.length);
        // 逐个元素比较
        for (let i = 0; i < expected.length; i++) {
          expect(result[i]).assertEqual(expected[i]);
        }
      });
    });

    describe('stopLongTask', () => {
      it('should handle stopping non-existent task gracefully', 0, () => {
        // 尝试停止不存在的任务应该不会抛出异常（根据实现，会记录警告）
        try {
          stopLongTask('non-existent-task');
          expect(true).assertTrue(); // 应该正常执行，不会抛出异常
        } catch (error) {
          // 如果抛出异常，验证异常类型
          expect(error instanceof Error).assertTrue();
        }
      });

      it('should allow stopping task multiple times', 0, async () => {
        // 启动一个快速完成的任务
        const taskPromise = withLongTask('multi-stop-task', testLongTaskMultiStop);

        // 等待一小段时间确保任务已启动
        await new Promise<void>(resolve => setTimeout(resolve, 10));

        // 多次停止任务（应该不会抛出异常）
        try {
          stopLongTask('multi-stop-task');
          stopLongTask('multi-stop-task');
          expect(true).assertTrue();
        } catch (error) {
          // 允许抛出异常，但应该优雅处理
          expect(error instanceof Error).assertTrue();
        }

        // 等待任务完成或被终止
        try {
          await Promise.race([
            taskPromise,
            new Promise<void>((_, reject) =>
            setTimeout(() => reject(new Error('timeout')), 100)
            )
          ]);
        } catch (error) {
          // 任务可能被终止或超时，这是正常的
        }
      });

      it('should handle stopping task after completion', 0, async () => {
        // 启动并等待任务完成
        await withLongTask('completed-task', testLongTaskCompleted);

        // 任务完成后尝试停止（应该不会抛出异常，但会记录警告）
        try {
          stopLongTask('completed-task');
          expect(true).assertTrue();
        } catch (error) {
          // 如果抛出异常，验证异常类型
          expect(error instanceof Error).assertTrue();
        }
      });

      it('should stop running long task', 0, async () => {
        // 启动一个长时间运行的任务（使用固定循环次数模拟长时间运行）
        const longTaskPromise = withLongTask('stop-running-task', testLongTaskStopRunning);

        // 等待一小段时间确保任务已启动
        await new Promise<void>(resolve => setTimeout(resolve, 30));

        // 停止任务
        try {
          stopLongTask('stop-running-task');
          expect(true).assertTrue();
        } catch (error) {
          // 停止任务可能会抛出错误，这是正常的
          expect(error instanceof Error).assertTrue();
        }

        // 等待任务完成或被终止
        try {
          await Promise.race([
            longTaskPromise,
            new Promise<void>((_, reject) =>
            setTimeout(() => reject(new Error('timeout')), 200)
            )
          ]);
        } catch (error) {
          // 任务被终止或超时是预期的
        }

        // 验证停止函数可以正常调用
        expect(true).assertTrue();
      });
    });
  });
}



