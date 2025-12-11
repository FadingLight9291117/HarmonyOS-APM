export const add: (a: number, b: number) => number;

/**
 * 初始化 native 崩溃处理
 * 注册信号处理函数，拦截 SIGSEGV、SIGABRT 等崩溃信号
 * @returns 初始化是否成功
 */
export const initCrashHandler: () => boolean;

/**
 * 检查是否有待处理的崩溃文件
 * @returns 崩溃文件路径，如果没有则返回 null
 */
export const checkPendingCrash: () => string | null;

/**
 * 检查崩溃通知标志（实时检测）
 * @returns 如果检测到崩溃通知返回 true，否则返回 false
 */
export const checkCrashNotifyFlag: () => boolean;

/**
 * 测试崩溃（用于测试）
 * 触发一个 SIGSEGV 信号用于测试崩溃处理流程
 * @warning 此方法会导致应用崩溃，仅用于测试
 */
export const testCrash: () => void;

/**
 * 设置回调函数
 * 从 ArkTS 传入一个回调函数，native 层可以在需要时调用
 * @param callback 回调函数，接收一个字符串参数
 * @returns 设置是否成功
 * 
 * @example
 * ```typescript
 * testNapi.setCallback((message: string) => {
 *   console.log('Callback invoked with:', message);
 * });
 * ```
 */
export const setCallback: (callback: (message: string) => void) => boolean;

/**
 * 调用回调函数（用于测试）
 * 手动触发回调函数，用于测试回调机制
 * @param message 可选，传递给回调函数的消息，默认为 "Test callback message"
 * @returns 调用是否成功
 * 
 * @example
 * ```typescript
 * testNapi.setCallback((msg) => console.log(msg));
 * testNapi.invokeCallback("Hello from native!");
 * ```
 */
export const invokeCallback: (message?: string) => boolean;
