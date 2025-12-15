export const add: (a: number, b: number) => number;

// ==================== 崩溃模拟函数 ====================

/**
 * 触发 SIGSEGV（段错误）- 空指针解引用
 * @warning 此方法会导致应用崩溃
 */
export const crashNullPointer: () => void;

/**
 * 触发 SIGSEGV（段错误）- 非法内存访问
 * @warning 此方法会导致应用崩溃
 */
export const crashInvalidMemory: () => void;

/**
 * 触发 SIGABRT（中止信号）- 调用 abort()
 * @warning 此方法会导致应用崩溃
 */
export const crashAbort: () => void;

/**
 * 触发 SIGFPE（浮点异常）- 整数除以零
 * @warning 此方法会导致应用崩溃
 */
export const crashDivideByZero: () => void;

/**
 * 触发 SIGBUS（总线错误）- 未对齐的内存访问
 * @warning 此方法会导致应用崩溃（取决于平台）
 */
export const crashBusError: () => void;

/**
 * 触发栈溢出 - 无限递归导致 SIGSEGV
 * @warning 此方法会导致应用崩溃
 */
export const crashStackOverflow: () => void;

/**
 * 触发 SIGILL（非法指令）
 * @warning 此方法会导致应用崩溃
 */
export const crashIllegalInstruction: () => void;

/**
 * 触发 SIGTRAP（断点/陷阱）
 * @warning 此方法会导致应用崩溃
 */
export const crashTrap: () => void;

/**
 * 在子线程中触发崩溃（SIGSEGV）
 * @warning 此方法会导致应用崩溃
 */
export const crashInThread: () => void;

/**
 * 堆缓冲区溢出 - 写入越界
 * @warning 此方法会导致应用崩溃或未定义行为
 */
export const crashHeapOverflow: () => void;

/**
 * 双重释放（Double Free）
 * @warning 此方法会导致应用崩溃（通常是 SIGABRT）
 */
export const crashDoubleFree: () => void;

/**
 * 释放后使用（Use After Free）
 * @warning 此方法会导致应用崩溃或未定义行为
 */
export const crashUseAfterFree: () => void;
