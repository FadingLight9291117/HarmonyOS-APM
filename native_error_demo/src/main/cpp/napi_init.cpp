#include "napi/native_api.h"
#include <cstdlib>
#include <cstring>
#include <csignal>
#include <pthread.h>

static napi_value Add(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};

    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_valuetype valuetype0;
    napi_typeof(env, args[0], &valuetype0);

    napi_valuetype valuetype1;
    napi_typeof(env, args[1], &valuetype1);

    double value0;
    napi_get_value_double(env, args[0], &value0);

    double value1;
    napi_get_value_double(env, args[1], &value1);

    napi_value sum;
    napi_create_double(env, value0 + value1, &sum);

    return sum;

}

// ==================== 崩溃模拟函数 ====================

/**
 * 触发 SIGSEGV（段错误）- 空指针解引用
 */
static napi_value CrashNullPointer(napi_env env, napi_callback_info info) {
    int* ptr = nullptr;
    *ptr = 42;  // 空指针写入，触发 SIGSEGV
    return nullptr;
}

/**
 * 触发 SIGSEGV（段错误）- 非法内存访问
 */
static napi_value CrashInvalidMemory(napi_env env, napi_callback_info info) {
    int* ptr = (int*)0xDEADBEEF;  // 非法地址
    *ptr = 42;  // 访问非法内存，触发 SIGSEGV
    return nullptr;
}

/**
 * 触发 SIGABRT（中止信号）- 调用 abort()
 */
static napi_value CrashAbort(napi_env env, napi_callback_info info) {
    abort();  // 触发 SIGABRT
    return nullptr;
}

/**
 * 触发 SIGFPE（浮点异常）- 整数除以零
 * 注意：ARM 架构下整数除以零通常不会触发硬件异常（结果为0），
 * 为了演示 SIGFPE，这里手动触发信号。
 */
static napi_value CrashDivideByZero(napi_env env, napi_callback_info info) {
    // volatile int a = 1;
    // volatile int b = 0;
    // volatile int c = a / b;  // ARM 上这通常不会崩溃
    // (void)c;
    
    raise(SIGFPE); // 手动触发 SIGFPE
    return nullptr;
}

/**
 * 触发 SIGBUS（总线错误）- 未对齐的内存访问
 * 注意：现代 ARM 架构通常支持非对齐访问，不会触发 SIGBUS。
 * 这里手动触发信号以演示。
 */
static napi_value CrashBusError(napi_env env, napi_callback_info info) {
    // char* buffer = (char*)malloc(sizeof(int) + 1);
    // int* misaligned = (int*)(buffer + 1);
    // *misaligned = 42;
    // free(buffer);
    
    raise(SIGBUS); // 手动触发 SIGBUS
    return nullptr;
}

/**
 * 触发 SIGSEGV - 栈溢出（递归调用）
 */
static void recursiveFunction(int depth) {
    char largeBuffer[4096];  // 占用栈空间
    memset(largeBuffer, 0, sizeof(largeBuffer));
    recursiveFunction(depth + 1);  // 无限递归
}

static napi_value CrashStackOverflow(napi_env env, napi_callback_info info) {
    recursiveFunction(0);  // 栈溢出，最终触发 SIGSEGV
    return nullptr;
}

/**
 * 触发 SIGILL（非法指令）
 */
static napi_value CrashIllegalInstruction(napi_env env, napi_callback_info info) {
    raise(SIGILL);  // 直接发送 SIGILL 信号
    return nullptr;
}

/**
 * 触发 SIGTRAP（断点/陷阱）
 */
static napi_value CrashTrap(napi_env env, napi_callback_info info) {
    raise(SIGTRAP);  // 直接发送 SIGTRAP 信号
    return nullptr;
}

/**
 * 在子线程中触发崩溃
 */
static void* threadCrashFunction(void* arg) {
    int* ptr = nullptr;
    *ptr = 42;  // 在子线程中触发崩溃
    return nullptr;
}

static napi_value CrashInThread(napi_env env, napi_callback_info info) {
    pthread_t thread;
    pthread_create(&thread, nullptr, threadCrashFunction, nullptr);
    pthread_join(thread, nullptr);
    return nullptr;
}

/**
 * 堆缓冲区溢出（写入越界）
 */
static napi_value CrashHeapOverflow(napi_env env, napi_callback_info info) {
    char* buffer = (char*)malloc(10);
    memset(buffer, 'A', 1000);  // 写入远超分配大小的数据
    free(buffer);
    return nullptr;
}

/**
 * 双重释放（Double Free）
 */
static napi_value CrashDoubleFree(napi_env env, napi_callback_info info) {
    char* buffer = (char*)malloc(100);
    free(buffer);
    free(buffer);  // 双重释放，可能触发 SIGABRT
    return nullptr;
}

/**
 * 释放后使用（Use After Free）
 * 注意：UAF 通常不会立即导致崩溃（除非开启 ASan），而是导致数据损坏。
 * 这里手动触发 SIGSEGV 来模拟“踩坏内存导致崩溃”的后果。
 */
static napi_value CrashUseAfterFree(napi_env env, napi_callback_info info) {
    char* buffer = (char*)malloc(100);
    free(buffer);
    // memset(buffer, 'A', 100);  // 实际通常不崩
    
    raise(SIGSEGV); // 手动触发 SIGSEGV 模拟后果
    return nullptr;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        // 崩溃模拟函数
        { "crashNullPointer", nullptr, CrashNullPointer, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashInvalidMemory", nullptr, CrashInvalidMemory, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashAbort", nullptr, CrashAbort, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashDivideByZero", nullptr, CrashDivideByZero, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashBusError", nullptr, CrashBusError, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashStackOverflow", nullptr, CrashStackOverflow, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashIllegalInstruction", nullptr, CrashIllegalInstruction, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashTrap", nullptr, CrashTrap, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashInThread", nullptr, CrashInThread, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashHeapOverflow", nullptr, CrashHeapOverflow, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashDoubleFree", nullptr, CrashDoubleFree, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "crashUseAfterFree", nullptr, CrashUseAfterFree, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "native_error_demo",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterNative_error_demoModule(void)
{
    napi_module_register(&demoModule);
}
