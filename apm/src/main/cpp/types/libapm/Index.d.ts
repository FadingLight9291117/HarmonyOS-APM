/**
 * 初始化 native 崩溃处理
 * 注册信号处理函数，拦截 SIGSEGV、SIGABRT 等崩溃信号
 * @param cacheDir 崩溃日志缓存目录
 * @param timeout 崩溃后等待 ArkTS 处理的超时时间（秒），默认为 3 秒
 * @returns 初始化是否成功
 */
export const initCrashHandler: (cacheDir: string, timeout?: number) => boolean;

/**
 * 检查是否有待处理的崩溃文件
 * @returns 崩溃文件路径，如果没有则返回 null
 */
export const checkPendingCrash: () => string | null;

/**
 * 检查崩溃通知标志（实时检测）
 * @returns 包含检测状态和崩溃信息的对象
 */
export const checkCrashState: () => {
    detected: boolean;
    crashName?: string;
    crashReason?: string;
};

/**
 * 设置回调函数
 * 从 ArkTS 传入一个回调函数，native 层可以在需要时调用
 * @param callback 回调函数，接收一个字符串参数
 * @returns 设置是否成功
 */
export const setCallback: (callback: (message: string) => void) => boolean;


/**
 * 通知 Native 层崩溃处理已完成
 * 当 ArkTS 层完成崩溃信息上传等处理后调用此函数，
 * 通知 Native 层可以安全退出应用
 * @returns 如果成功发送信号返回 true，如果没有待处理的崩溃返回 false
 */
export const notifyCrashHandled: () => boolean;


/**
 * 调用回调函数（用于测试）
 * 手动触发回调函数，用于测试回调机制
 * @param message 可选，传递给回调函数的消息，默认为 "Test callback message"
 * @returns 调用是否成功
 */
export const invokeCallback: (message?: string) => boolean;
