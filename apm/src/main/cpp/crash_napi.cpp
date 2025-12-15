/**
 * crash_handler.cpp
 *
 * NAPI 函数实现
 * 提供给 ArkTS 层调用的接口
 */

#include "crash_handler.h"
#include <cstring>
#include <fstream>
#include <string>
#include <hilog/log.h>
#include <unistd.h>
#include <hilog/log.h>
#include "BasicServicesKit/oh_commonevent.h"

// ==================== 回调函数处理 ====================

void invoke_callback(const char *message) {
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

// ==================== NAPI 函数实现 ====================

extern "C" napi_value InitCrashHandler(napi_env env, napi_callback_info info) {
    // 获取参数
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc > 0) {
        napi_valuetype valuetype;
        napi_typeof(env, args[0], &valuetype);
        if (valuetype == napi_string) {
            size_t result = 0;
            char buf[1024] = {0};
            napi_get_value_string_utf8(env, args[0], buf, sizeof(buf), &result);
            g_cache_dir = buf;
            OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "CrashHandler", "Cache dir set to: %{public}s", g_cache_dir.c_str());
        }
    }

    if (argc > 1) {
        napi_valuetype valuetype;
        napi_typeof(env, args[1], &valuetype);
        if (valuetype == napi_number) {
            int32_t timeout = 0;
            napi_get_value_int32(env, args[1], &timeout);
            if (timeout > 0) {
                g_crash_timeout = timeout;
                OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "CrashHandler", "Crash timeout set to: %{public}d", g_crash_timeout);
            }
        }
    }

    // 保存环境引用
    g_env = env;

    // 保存主线程 ID
    g_main_thread_id = pthread_self();

    // 注册主线程的信号处理函数
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

extern "C" napi_value CheckCrashState(napi_env env, napi_callback_info info) {
    bool detected = g_crash_detected;
    if (detected) {
        g_crash_detected = false;
    }

    napi_value result;
    napi_create_object(env, &result);

    napi_value detectedValue;
    napi_get_boolean(env, detected, &detectedValue);
    napi_set_named_property(env, result, "detected", detectedValue);

    if (detected) {
        napi_value nameValue;
        napi_create_string_utf8(env, g_last_crash_name, NAPI_AUTO_LENGTH, &nameValue);
        napi_set_named_property(env, result, "crashName", nameValue);

        napi_value reasonValue;
        napi_create_string_utf8(env, g_last_crash_reason, NAPI_AUTO_LENGTH, &reasonValue);
        napi_set_named_property(env, result, "crashReason", reasonValue);
    }

    return result;
}

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

    // 保存环境引用
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

extern "C" napi_value InvokeCallback(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};

    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    const char *default_message = "Test callback message";
    char *dynamic_message = nullptr;
    const char *message = default_message;

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

    if (dynamic_message != nullptr) {
        delete[] dynamic_message;
    }

    napi_value result;
    napi_get_boolean(env, true, &result);
    return result;
}

extern "C" napi_value NotifyCrashHandled(napi_env env, napi_callback_info info) {
    if (g_crash_thread_id != 0) {
        OH_LOG_Print(LOG_APP, LOG_INFO, 0xFF00, "CrashHandler", "ArkTS notified crash handled, sending signal to crash thread");
        pthread_kill(g_crash_thread_id, ARKTS_DONE_SIG);

        napi_value result;
        napi_get_boolean(env, true, &result);
        return result;
    }

    OH_LOG_Print(LOG_APP, LOG_WARN, 0xFF00, "CrashHandler", "NotifyCrashHandled called but no crash pending");
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
}
