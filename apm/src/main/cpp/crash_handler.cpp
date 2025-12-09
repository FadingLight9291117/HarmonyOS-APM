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

// 全局变量
static napi_env g_env = nullptr;
static napi_ref g_upload_callback_ref = nullptr;
static pthread_mutex_t g_crash_mutex = PTHREAD_MUTEX_INITIALIZER;
static bool g_crash_handled = false;
static const int MAX_STACK_FRAMES = 64;
static void* g_stack_frames[MAX_STACK_FRAMES];
static const char* CRASH_FLAG_FILE = "/data/storage/el2/base/cache/.crash_pending";

// 信号名称映射
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

// 保存崩溃信息到文件
static std::string save_crash_to_file(int sig, const char* signal_name) {
    std::string crash_info = create_crash_info(sig, signal_name);
    std::string file_path = "/data/storage/el2/base/cache/crash_info_";
    file_path += std::to_string(getpid());
    file_path += "_";
    file_path += std::to_string(time(nullptr));
    file_path += ".json";
    
    std::ofstream file(file_path);
    if (file.is_open()) {
        file << crash_info;
        file.close();
        return file_path;
    }
    
    return "";
}

// 标记崩溃文件，让主线程处理上传
static void mark_crash_for_upload(const char* crash_file_path) {
    // 将崩溃文件路径写入标志文件
    std::ofstream flag_file(CRASH_FLAG_FILE);
    if (flag_file.is_open()) {
        flag_file << crash_file_path;
        flag_file.close();
    }
    
    // 尝试从主线程触发上传（使用更安全的方式）
    // 注意：在信号处理函数中直接调用 NAPI 是不安全的
    // 这里我们只是标记文件，让主线程轮询处理
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
    
    // 保存崩溃信息到文件
    std::string crash_file = save_crash_to_file(sig, signal_name);
    
    if (!crash_file.empty()) {
        // 标记崩溃文件，让主线程处理上传
        mark_crash_for_upload(crash_file.c_str());
        
        // 等待上传完成（给 ETS 层一些时间）
        // 注意：这里不能等待太久，否则系统可能会强制杀死进程
        // 使用 alarm 设置超时，防止无限等待
        alarm(5); // 5 秒后强制退出
        sleep(5); // 等待最多 5 秒让上传完成
        alarm(0); // 取消 alarm
    }
    
    pthread_mutex_unlock(&g_crash_mutex);
    
    // 恢复默认信号处理并重新发送信号，让系统正常处理崩溃
    signal(sig, SIG_DFL);
    raise(sig);
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
    // 保存环境引用（用于后续可能的调用）
    g_env = env;
    
    // 注册信号处理
    register_signal_handlers();
    
    napi_value result;
    napi_get_boolean(env, true, &result);
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
    
    // 删除标志文件
    unlink(CRASH_FLAG_FILE);
    
    napi_value result;
    napi_create_string_utf8(env, crash_file_path.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

// NAPI: 测试崩溃（用于测试）
extern "C" napi_value TestCrash(napi_env env, napi_callback_info info) {
    // 触发一个崩溃用于测试
    int* p = nullptr;
    *p = 42; // 这将触发 SIGSEGV
    return nullptr;
}

