#include "napi/native_api.h"
#include "crash_handler.h"

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"initCrashHandler", nullptr, InitCrashHandler, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"checkPendingCrash", nullptr, CheckPendingCrash, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"checkCrashState", nullptr, CheckCrashState, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setCallback", nullptr, SetCallback, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"invokeCallback", nullptr, InvokeCallback, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"notifyCrashHandled", nullptr, NotifyCrashHandled, nullptr, nullptr, nullptr, napi_default, nullptr}};
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
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterApmModule(void) { napi_module_register(&demoModule); }
