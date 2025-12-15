#ifndef CRASH_HANDLER_H
#define CRASH_HANDLER_H

#include "napi/native_api.h"
#include <signal.h>
#include <pthread.h>
#include <string>

// ==================== 全局变量声明 ====================

// NAPI 环境
extern napi_env g_env;

// 崩溃处理状态
extern pthread_mutex_t g_crash_mutex;

// 堆栈帧
extern const int MAX_STACK_FRAMES;
extern void* g_stack_frames[];

// 崩溃文件路径
extern const char* CRASH_FLAG_FILE;
extern std::string g_cache_dir;
extern int g_crash_timeout;

// 实时检测相关
extern volatile bool g_crash_detected;
extern char g_last_crash_name[64];
extern char g_last_crash_reason[128];
extern pthread_t g_main_thread_id;
extern pthread_t g_crash_thread_id;
extern const int CRASH_NOTIFY_SIG;
extern const int ARKTS_DONE_SIG;
extern volatile int g_pending_crash_signal;
extern volatile bool g_arkts_done;

// 回调函数相关
extern napi_ref g_callback_ref;
extern pthread_mutex_t g_callback_mutex;

// ==================== 信号处理函数声明 ====================
void invoke_callback(const char *message);

/**
 * 获取信号名称
 */
const char* get_signal_name(int sig);

/**
 * 收集堆栈信息
 */
std::string collect_backtrace();

/**
 * 创建崩溃信息 JSON
 */
std::string create_crash_info(int sig, const char* signal_name);

/**
 * 生成崩溃文件路径
 */
std::string generate_crash_file_path();

/**
 * 保存崩溃信息到文件
 */
std::string save_crash_to_file(int sig, const char* signal_name, const std::string& file_path);

/**
 * 标记崩溃文件，让主线程处理上传
 */
void mark_crash_for_upload(const char* crash_file_path);

/**
 * 设置延迟退出机制
 */
void setup_delayed_exit(int sig, int timeout_seconds = 5);

/**
 * 等待 ArkTS 完成信号或超时后退出
 */
void wait_for_arkts_and_exit();

/**
 * 注册崩溃信号处理
 */
void register_signal_handlers();

/**
 * 主线程的信号处理函数
 */
void crash_notify_handler(int sig);

// ==================== NAPI 函数声明 ====================

extern "C" {
    napi_value InitCrashHandler(napi_env env, napi_callback_info info);
    napi_value CheckPendingCrash(napi_env env, napi_callback_info info);
    napi_value CheckCrashState(napi_env env, napi_callback_info info);
    napi_value SetCallback(napi_env env, napi_callback_info info);
    napi_value InvokeCallback(napi_env env, napi_callback_info info);
    napi_value NotifyCrashHandled(napi_env env, napi_callback_info info);
}

#endif // CRASH_HANDLER_H
