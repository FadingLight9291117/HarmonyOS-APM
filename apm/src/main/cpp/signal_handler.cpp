/**
 * signal_handler.cpp
 * 
 * 信号处理相关函数实现
 * 包括：信号捕获、崩溃信息收集、文件保存、延迟退出机制
 */

#include "crash_handler.h"
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <execinfo.h>
#include <cstring>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <sstream>
#include <string>
#include <hilog/log.h>
#include "BasicServicesKit/oh_commonevent.h"

// ==================== 全局变量定义 ====================

napi_env g_env = nullptr;
pthread_mutex_t g_crash_mutex = PTHREAD_MUTEX_INITIALIZER;
const int MAX_STACK_FRAMES = 64;
void* g_stack_frames[MAX_STACK_FRAMES];
const char* CRASH_FLAG_FILE = "/data/storage/el2/base/cache/.crash_pending";
std::string g_cache_dir = "/data/storage/el2/base/cache";
int g_crash_timeout = 3;

volatile bool g_crash_detected = false;
char g_last_crash_name[64] = {0};
char g_last_crash_reason[128] = {0};
pthread_t g_main_thread_id = 0;
pthread_t g_crash_thread_id = 0;
const int CRASH_NOTIFY_SIG = SIGUSR1;
const int ARKTS_DONE_SIG = SIGUSR2;
volatile int g_pending_crash_signal = 0;
volatile bool g_arkts_done = false;
volatile long long g_crash_start_time = 0;

napi_ref g_callback_ref = nullptr;
pthread_mutex_t g_callback_mutex = PTHREAD_MUTEX_INITIALIZER;

// ==================== 辅助函数 ====================

const char* get_signal_name(int sig) {
    switch (sig) {
        case SIGSEGV: return "SIGSEGV";
        case SIGABRT: return "SIGABRT";
        case SIGFPE: return "SIGFPE";
        case SIGILL: return "SIGILL";
        case SIGBUS: return "SIGBUS";
        case SIGTRAP: return "SIGTRAP";
        default: return "Unknown signal";
    }
}

const char* get_signal_reason(int sig, siginfo_t* info) {
    if (info == nullptr) {
        return "Unknown reason";
    }
    
    switch (sig) {
        case SIGSEGV:
            switch (info->si_code) {
                case SEGV_MAPERR: return "Address not mapped to object";
                case SEGV_ACCERR: return "Invalid permissions for mapped object";
                default: return "Segmentation fault";
            }
        case SIGABRT:
            return "Process abort signal";
        case SIGFPE:
            switch (info->si_code) {
                case FPE_INTDIV: return "Integer divide by zero";
                case FPE_INTOVF: return "Integer overflow";
                case FPE_FLTDIV: return "Floating-point divide by zero";
                case FPE_FLTOVF: return "Floating-point overflow";
                case FPE_FLTUND: return "Floating-point underflow";
                case FPE_FLTRES: return "Floating-point inexact result";
                case FPE_FLTINV: return "Invalid floating-point operation";
                case FPE_FLTSUB: return "Subscript out of range";
                default: return "Floating-point exception";
            }
        case SIGILL:
            switch (info->si_code) {
                case ILL_ILLOPC: return "Illegal opcode";
                case ILL_ILLOPN: return "Illegal operand";
                case ILL_ILLADR: return "Illegal addressing mode";
                case ILL_ILLTRP: return "Illegal trap";
                case ILL_PRVOPC: return "Privileged opcode";
                case ILL_PRVREG: return "Privileged register";
                case ILL_COPROC: return "Coprocessor error";
                case ILL_BADSTK: return "Internal stack error";
                default: return "Illegal instruction";
            }
        case SIGBUS:
            switch (info->si_code) {
                case BUS_ADRALN: return "Invalid address alignment";
                case BUS_ADRERR: return "Nonexistent physical address";
                case BUS_OBJERR: return "Object-specific hardware error";
                default: return "Bus error";
            }
        case SIGTRAP:
            switch (info->si_code) {
                case TRAP_BRKPT: return "Process breakpoint";
                case TRAP_TRACE: return "Process trace trap";
                default: return "Trace/breakpoint trap";
            }
        default:
            return "Unknown signal";
    }
}

std::string collect_backtrace() {
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

// ==================== 崩溃信息处理 ====================

std::string create_crash_info(int sig, const char* signal_name, const char* signal_reason, siginfo_t* info) {
    std::ostringstream oss;
    std::string backtrace_str = collect_backtrace();
    
    // 获取故障地址
    void* fault_addr = (info != nullptr) ? info->si_addr : nullptr;
    
    oss << "{\n";
    oss << "  \"signal\": " << sig << ",\n";
    oss << "  \"signal_name\": \"" << signal_name << "\",\n";
    oss << "  \"pid\": " << getpid() << ",\n";
    oss << "  \"tid\": " << pthread_self() << ",\n";
    oss << "  \"time\": " << (long long)(time(nullptr) * 1000) << ",\n";
    oss << "  \"crash_type\": \"NativeCrash\",\n";
    oss << "  \"crash_name\": \"" << signal_name << "\",\n";
    oss << "  \"crash_reason\": \"" << signal_reason << "\",\n";
    if (fault_addr != nullptr) {
        oss << "  \"fault_addr\": \"0x" << std::hex << reinterpret_cast<uintptr_t>(fault_addr) << std::dec << "\",\n";
    }
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

std::string generate_crash_file_path() {
    std::string file_path = g_cache_dir + "/crash_info_";
    file_path += std::to_string(getpid());
    file_path += "_";
    file_path += std::to_string(time(nullptr));
    file_path += ".json";
    return file_path;
}

std::string save_crash_to_file(int sig, const char* signal_name, const char* signal_reason, 
                               siginfo_t* info, const std::string& file_path) {
    std::string crash_info = create_crash_info(sig, signal_name, signal_reason, info);
    
    std::ofstream file(file_path);
    if (file.is_open()) {
        file << crash_info;
        file.close();
        return file_path;
    }
    
    return "";
}

void mark_crash_for_upload(const char* crash_file_path) {
    // 将崩溃文件路径写入标志文件
    std::ofstream flag_file(CRASH_FLAG_FILE);
    if (flag_file.is_open()) {
        flag_file << crash_file_path;
        flag_file.close();
    }
    
    // 向主线程发送通知信号
    if (g_main_thread_id != 0) {
        pthread_kill(g_main_thread_id, CRASH_NOTIFY_SIG);
    }
}

// ==================== 信号处理函数 ====================

void crash_notify_handler(int sig) {
    // 只设置标志，不阻塞，让主线程的事件循环继续执行
    g_crash_detected = true;
}

// SIGALRM 处理函数：超时强制退出
static void alarm_handler(int sig) {
    OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "CrashHandler", "Timeout waiting for ArkTS, force exit");
    if (g_pending_crash_signal != 0) {
        signal(g_pending_crash_signal, SIG_DFL);
        sigset_t set;
        sigemptyset(&set);
        sigaddset(&set, g_pending_crash_signal);
        sigprocmask(SIG_UNBLOCK, &set, nullptr);
        raise(g_pending_crash_signal);
    } else {
        _exit(1);
    }
}

// ArkTS 完成信号处理函数
static void arkts_done_handler(int sig) {
    g_arkts_done = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "CrashHandler", "Received ArkTS done signal, exiting gracefully");
}

// ==================== 延迟退出机制 ====================

void setup_delayed_exit(int sig, int timeout_seconds) {
    g_pending_crash_signal = sig;
    g_crash_thread_id = pthread_self();
    g_arkts_done = false;
    g_crash_start_time = (long long)(time(nullptr) * 1000);
    
    // 注册 ArkTS 完成信号处理函数
    struct sigaction done_sa = {};
    done_sa.sa_handler = arkts_done_handler;
    sigemptyset(&done_sa.sa_mask);
    sigaction(ARKTS_DONE_SIG, &done_sa, nullptr);
    
    // 注册 SIGALRM 超时处理函数
    struct sigaction alarm_sa = {};
    alarm_sa.sa_handler = alarm_handler;
    sigemptyset(&alarm_sa.sa_mask);
    sigaction(SIGALRM, &alarm_sa, nullptr);
    
    // 阻止原始崩溃信号，防止立即退出
    sigset_t set;
    sigemptyset(&set);
    sigaddset(&set, sig);
    sigprocmask(SIG_BLOCK, &set, nullptr);
    
    // 设置超时
    alarm(timeout_seconds);
}

void wait_for_arkts_and_exit() {
    sigset_t wait_set;
    sigfillset(&wait_set);
    sigdelset(&wait_set, SIGALRM);
    sigdelset(&wait_set, ARKTS_DONE_SIG);
    
    // 等待信号（ArkTS 完成或超时）
    while (!g_arkts_done) {
        sigsuspend(&wait_set);
        if (g_arkts_done) {
            long long elapsed_time = (long long)(time(nullptr) * 1000) - g_crash_start_time;
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "CrashHandler", 
                         "ArkTS processing completed, elapsed time: %{public}lld ms, exiting", elapsed_time);
            break;
        }
    }
    
    // 取消 alarm
    alarm(0);
    
    // 正常退出
    _exit(0);
}

// ==================== 崩溃信号处理 ====================

static void crash_signal_handler(int sig, siginfo_t* info, void* context) {
    // 1. 简单的防重入检查 (不使用 pthread_mutex，防止死锁)
    static volatile bool has_crashed = false;
    if (has_crashed) {
        _exit(1);
    }
    has_crashed = true;

    const char* signal_name = get_signal_name(sig);
    const char* signal_reason = get_signal_reason(sig, info);
    
    // 保存崩溃信息到全局变量，供 NAPI 读取
    strncpy(g_last_crash_name, signal_name, sizeof(g_last_crash_name) - 1);
    strncpy(g_last_crash_reason, signal_reason, sizeof(g_last_crash_reason) - 1);

    // 2. 使用 fork 在子进程中处理耗时/危险操作
    pid_t pid = fork();

    if (pid == 0) {
//        invoke_callback("CrashHandler: Native crash detected. 子进程");
        // === 子进程 ===
        // 在这里可以相对安全地分配内存、写文件

        // 生成并保存日志
        std::string crash_file = save_crash_to_file(sig, signal_name, signal_reason, info, generate_crash_file_path());

        if (!crash_file.empty()) {
            mark_crash_for_upload(crash_file.c_str());
            // 子进程不需要等待 ArkTS，只负责写文件
        }

        _exit(0); // 子进程处理完立即退出
    } else if (pid > 0) {
//        invoke_callback("CrashHandler: Native crash detected. 父进程");
        // === 父进程 ===
        // 等待子进程完成日志写入
        int status;
        waitpid(pid, &status, 0);

        // 父进程继续执行原有的通知和等待逻辑
        OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "CrashHandler", 
                     "Native crash detected. (%{public}s: %{public}s)", g_last_crash_name, g_last_crash_reason);
    

        // 先设置延迟退出环境（包括设置 g_crash_thread_id），确保 ArkTS 回调时状态已就绪
        setup_delayed_exit(sig, g_crash_timeout);

        // 触发通知逻辑
        if (g_main_thread_id != 0) {
            pthread_kill(g_main_thread_id, CRASH_NOTIFY_SIG);
        }

        wait_for_arkts_and_exit();
    }

//    
//    // 2. 先设置延迟退出环境，确保 ArkTS 回调时状态已就绪
//    OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "CrashHandler", "Native crash detected. (%{public}s: %{public}s)", g_last_crash_name, g_last_crash_reason);
//    setup_delayed_exit(sig, g_crash_timeout);
//    wait_for_arkts_and_exit();

    // 3. 恢复默认信号处理并重新抛出
    signal(sig, SIG_DFL);
    raise(sig);
}

void register_signal_handlers() {
    invoke_callback("CrashHandler: Native crash detected. register_signal_handlers");
    
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
