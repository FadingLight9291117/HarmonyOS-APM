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
 * 测试崩溃（用于测试）
 * 触发一个 SIGSEGV 信号用于测试崩溃处理流程
 * @warning 此方法会导致应用崩溃，仅用于测试
 */
export const testCrash: () => void;