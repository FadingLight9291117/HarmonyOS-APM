#include "napi/native_api.h"
#include <signal.h>
#include <unistd.h>
#include <sys/types.h>
#include <pthread.h>
#include <execinfo.h>
#include <cstring>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <hilog/log.h>

// 全局变量
static napi_env g_env = nullptr;
static pthread_mutex_t g_crash_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool g_crash_handled = false;
static const int MAX_STACK_FRAMES = 64;
static void* g_stack_frames[MAX_STACK_FRAMES];
static const char* CRASH_FLAG_FILE = "/data/storage/el2/base/cache/.crash_pending";

// 实时检测相关变量
static volatile bool g_crash_detected = false;  // 崩溃检测标志
static pthread_t g_main_thread_id = 0;  // 主线程 ID
static const int CRASH_NOTIFY_SIG = SIGUSR1;  // 用于通知主线程的专用信号
static volatile int g_pending_crash_signal = 0;  // 待处理的崩溃信号

// 回调函数相关变量
static napi_ref g_callback_ref = nullptr;  // 回调函数引用
static pthread_mutex_t g_callback_mutex = PTHREAD_MUTEX_INITIALIZER;  // 回调互斥锁

// 信号名称映射

// 调用回调函数（在主线程中安全调用）
static void invoke_callback(const char* message) {
    if (g_env == nullptr || g_callback_ref == nullptr) {
        return;
    }
    
    pthread_mutex_lock(&g_callback_mutex);
    
    napi_handle_scope scope;
    napi_open_handle_scope(g_env, &scope);
    
    // 获取回调函数
    napi_value callback;
    napi_status status = napi_get_reference_value(g_env, g_callback_ref, &callback);
    if (status != napi_ok) {
        napi_close_handle_scope(g_env, scope);
        pthread_mutex_unlock(&g_callback_mutex);
        return;
    }
    
    // 创建参数
    napi_value argv[1];
    napi_create_string_utf8(g_env, message, NAPI_AUTO_LENGTH, &argv[0]);
    
    // 调用回调函数
    napi_value global;
    napi_get_global(g_env, &global);
    napi_value result;
    napi_call_function(g_env, global, callback, 1, argv, &result);
    
    napi_close_handle_scope(g_env, scope);
    pthread_mutex_unlock(&g_callback_mutex);
}


static const char* get_signal_name(int sig) {
    switch (sig) {
        case SIGSEGV: return "SIGSEGV";
        case SIGABRT: return "SIGABRT";
        case SIGFPE: return "SIGFPE";
        case SIGILL: return "SIGILL";
        case SIGBUS: return "SIGBUS";
        case SIGTRAP: return "SIGTRAP";
        default: return "UNKNOWN";
    }
}

// 收集堆栈信息
static std::string collect_backtrace() {
    std::ostringstream oss;
    int size = backtrace(g_stack_frames, MAX_STACK_FRAMES);
    char** symbols = backtrace_symbols(g_stack_frames, size);
    
    if (symbols) {
        for (int i = 0; i < size; i++) {
            oss << symbols[i] << "\n";
        }
        free(symbols);
    }
    
    return oss.str();
}

// 创建崩溃信息 JSON
static std::string create_crash_info(int sig, const char* signal_name) {
    std::ostringstream oss;
    std::string backtrace_str = collect_backtrace();
    
    oss << "{\n";
    oss << "  \"signal\": " << sig << ",\n";
    oss << "  \"signal_name\": \"" << signal_name << "\",\n";
    oss << "  \"pid\": " << getpid() << ",\n";
    oss << "  \"tid\": " << pthread_self() << ",\n";
    oss << "  \"time\": " << (long long)(time(nullptr) * 1000) << ",\n";
    oss << "  \"crash_type\": \"NativeCrash\",\n";
    oss << "  \"backtrace\": [\n";
    
    // 解析 backtrace 字符串
    std::istringstream iss(backtrace_str);
    std::string line;
    bool first = true;
    while (std::getline(iss, line)) {
        if (!first) oss << ",\n";
        first = false;
        // 转义 JSON 字符串
        std::string escaped;
        for (char c : line) {
            if (c == '"') escaped += "\\\"";
            else if (c == '\\') escaped += "\\\\";
            else if (c == '\n') escaped += "\\n";
            else escaped += c;
        }
        oss << "    \"" << escaped << "\"";
    }
    oss << "\n  ]\n";
    oss << "}";
    
    return oss.str();
}

// 生成崩溃文件路径
static std::string generate_crash_file_path() {
    std::string file_path = "/data/storage/el2/base/cache/crash_info_";
    file_path += std::to_string(getpid());
    file_path += "_";
    file_path += std::to_string(time(nullptr));
    file_path += ".json";
    return file_path;
}

// 保存崩溃信息到文件
static std::string save_crash_to_file(int sig, const char* signal_name, const std::string& file_path) {
    std::string crash_info = create_crash_info(sig, signal_name);
    
    std::ofstream file(file_path);
    if (file.is_open()) {
        file << crash_info;
        file.close();
        return file_path;
    }
    
    return "";
}


// 主线程的信号处理函数（用于接收崩溃通知，在主线程中执行）
static void crash_notify_handler(int sig) {
    // 只设置标志，不阻塞，让主线程的事件循环继续执行
    g_crash_detected = true;
}

// SIGALRM 处理函数：延迟退出
static void alarm_handler(int sig) {
    // 3 秒后强制退出，重新发送原始崩溃信号
    if (g_pending_crash_signal != 0) {
        // 恢复原始信号的默认处理
        signal(g_pending_crash_signal, SIG_DFL);
        // 解除信号阻塞
        sigset_t set;
        sigemptyset(&set);
        sigaddset(&set, g_pending_crash_signal);
        sigprocmask(SIG_UNBLOCK, &set, nullptr);
        // 重新发送原始崩溃信号
        raise(g_pending_crash_signal);
    } else {
        _exit(1);
    }
}

// 标记崩溃文件，让主线程处理上传
static void mark_crash_for_upload(const char* crash_file_path) {
    // 将崩溃文件路径写入标志文件
    std::ofstream flag_file(CRASH_FLAG_FILE);
    if (flag_file.is_open()) {
        flag_file << crash_file_path;
        flag_file.close();
    }
    
    // 向主线程发送通知信号（不阻塞，让主线程有机会执行）
    if (g_main_thread_id != 0) {
        pthread_kill(g_main_thread_id, CRASH_NOTIFY_SIG);
    }
}

// 信号处理函数
static void crash_signal_handler(int sig, siginfo_t* info, void* context) {
    // 防止重复处理
    if (pthread_mutex_trylock(&g_crash_mutex) != 0) {
        // 如果已经处理过，直接退出
        _exit(1);
    }
    
    if (g_crash_handled) {
        pthread_mutex_unlock(&g_crash_mutex);
        _exit(1);
    }
    
    g_crash_handled = true;
    
    const char* signal_name = get_signal_name(sig);
    
    // 生成崩溃文件路径（在保存之前）
    std::string crash_file_path = generate_crash_file_path();
    
    // 保存崩溃信息到文件
    // 注意：在信号处理器中不能直接调用 NAPI 函数（不安全）
    // 回调函数将在 ETS 层的主线程中安全调
    std::string crash_file = save_crash_to_file(sig, signal_name, crash_file_path);
    
    OH_LOG_Print(LOG_APP, LOG_ERROR, 0xFF00, "CrashHandler", "Native crash detected. %{public}s saved to %{public}s", signal_name, crash_file.c_str());
    
    if (!crash_file.empty()) {
        // 标记崩溃文件，让主线程处理上传和回调
        mark_crash_for_upload(crash_file.c_str());
        
        // 保存原始崩溃信号，用于延迟退出时重新发送
        g_pending_crash_signal = sig;
        
        // 注册 SIGALRM 处理函数（延迟退出）
        struct sigaction alarm_sa;
        memset(&alarm_sa, 0, sizeof(alarm_sa));
        alarm_sa.sa_handler = alarm_handler;
        sigemptyset(&alarm_sa.sa_mask);
        alarm_sa.sa_flags = 0;
        sigaction(SIGALRM, &alarm_sa, nullptr);
        
        // 阻止原始崩溃信号，防止立即退出
        // 注意：必须在信号处理器返回前阻止信号，否则系统会立即终止进程
        sigset_t set;
        sigemptyset(&set);
        sigaddset(&set, sig);
        sigprocmask(SIG_BLOCK, &set, nullptr);
        
//        invoke_callback("test in native");
        
        // 设置 alarm，延迟退出，给主线程时间执行回调
        alarm(3); // 3 秒后强制退出
        
        // 重要：不恢复默认信号处理，保持当前处理
        // 这样信号处理器返回后，系统不会立即终止进程
        // 信号被阻塞，直到 alarm 触发时再恢复
        
        // 解锁互斥锁，让主线程可以继续执行
        pthread_mutex_unlock(&g_crash_mutex);
        
        // 使用 sigsuspend 等待，直到 alarm 触发
        // sigsuspend 会临时解除信号阻塞，等待任何信号
        // 当 alarm 触发 SIGALRM 时，alarm_handler 会处理退出
        sigset_t wait_set;
        sigfillset(&wait_set);
        sigdelset(&wait_set, SIGALRM);  // 允许 SIGALRM 通过
        sigsuspend(&wait_set);  // 等待 SIGALRM
        
        // 如果 sigsuspend 返回（不应该发生），直接退出
        _exit(1);
    }
    
    pthread_mutex_unlock(&g_crash_mutex);
    
    // 如果没有崩溃文件，直接退出
    _exit(1);
}

// 注册信号处理
static void register_signal_handlers() {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crash_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
    
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGABRT, &sa, nullptr);
    sigaction(SIGFPE, &sa, nullptr);
    sigaction(SIGILL, &sa, nullptr);
    sigaction(SIGBUS, &sa, nullptr);
    sigaction(SIGTRAP, &sa, nullptr);
}

// NAPI: 初始化崩溃处理
extern "C" napi_value InitCrashHandler(napi_env env, napi_callback_info info) {
    // 保存环境引用
    g_env = env;
    
    // 保存主线程 ID（用于实时通知）
    g_main_thread_id = pthread_self();
    
    // 注册主线程的信号处理函数（用于接收崩溃通知）
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = crash_notify_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(CRASH_NOTIFY_SIG, &sa, nullptr);
    
    // 注册崩溃信号处理
    register_signal_handlers();
    
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

// NAPI: 检查崩溃通知标志（实时检测）
extern "C" napi_value CheckCrashNotifyFlag(napi_env env, napi_callback_info info) {
    bool detected = g_crash_detected;
    if (detected) {
        g_crash_detected = false;  // 清除标志
    }
    
    napi_value result;
    napi_get_boolean(env, detected, &result);
    return result;
}

// NAPI: 检查是否有待处理的崩溃文件
extern "C" napi_value CheckPendingCrash(napi_env env, napi_callback_info info) {
    std::ifstream flag_file(CRASH_FLAG_FILE);
    if (!flag_file.is_open()) {
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }
    
    std::string crash_file_path;
    std::getline(flag_file, crash_file_path);
    flag_file.close();
    
    // 检查崩溃文件是否存在
    std::ifstream crash_file(crash_file_path);
    if (!crash_file.is_open()) {
        // 文件不存在，删除标志文件并返回 null
        unlink(CRASH_FLAG_FILE);
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }
    crash_file.close();
    
    // 文件存在，删除标志文件并返回路径
    unlink(CRASH_FLAG_FILE);
    
    napi_value result;
    napi_create_string_utf8(env, crash_file_path.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}


// NAPI: 设置回调函数
extern "C" napi_value SetCallback(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    if (argc < 1) {
        napi_throw_error(env, nullptr, "Expected 1 argument: callback function");
        return nullptr;
    }
    
    // 检查参数类型
    napi_valuetype valuetype;
    napi_typeof(env, args[0], &valuetype);
    if (valuetype != napi_function) {
        napi_throw_error(env, nullptr, "Argument must be a function");
        return nullptr;
    }
    
    pthread_mutex_lock(&g_callback_mutex);
    
    // 释放旧的引用
    if (g_callback_ref != nullptr) {
        napi_delete_reference(env, g_callback_ref);
        g_callback_ref = nullptr;
    }
    
    // 保存环境引用（如果还没有保存）
    if (g_env == nullptr) {
        g_env = env;
    }
    
    // 创建新的引用
    napi_create_reference(env, args[0], 1, &g_callback_ref);
    
    pthread_mutex_unlock(&g_callback_mutex);
    
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

// NAPI: 调用回调函数（用于测试）
extern "C" napi_value InvokeCallback(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    
    const char* default_message = "Test callback message";
    char* dynamic_message = nullptr;
    const char* message = default_message;
    
    if (argc >= 1) {
        napi_valuetype valuetype;
        napi_typeof(env, args[0], &valuetype);
        if (valuetype == napi_string) {
            size_t length = 0;
            napi_get_value_string_utf8(env, args[0], nullptr, 0, &length);
            dynamic_message = new char[length + 1];
            napi_get_value_string_utf8(env, args[0], dynamic_message, length + 1, &length);
            message = dynamic_message;
        }
    }
    
    invoke_callback(message);
    
    // 释放动态分配的内存
    if (dynamic_message != nullptr) {
        delete[] dynamic_message;
    }
    
    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

// NAPI: 测试崩溃（用于测试）
extern "C" napi_value TestCrash(napi_env env, napi_callback_info info) {
    // 触发一个崩溃用于测试
    int* p = nullptr;
    *p = 42; // 这将触发 SIGSEGV
    return nullptr;
}

