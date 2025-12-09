#include "napi/native_api.h"

// 声明来自 crash_handler.cpp 的函数
extern "C" {
    napi_value InitCrashHandler(napi_env env, napi_callback_info info);
    napi_value TestCrash(napi_env env, napi_callback_info info);
    napi_value CheckPendingCrash(napi_env env, napi_callback_info info);
}

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

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "initCrashHandler", nullptr, InitCrashHandler, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "testCrash", nullptr, TestCrash, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "checkPendingCrash", nullptr, CheckPendingCrash, nullptr, nullptr, nullptr, napi_default, nullptr }
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
    .nm_modname = "apm",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterApmModule(void)
{
    napi_module_register(&demoModule);
}
