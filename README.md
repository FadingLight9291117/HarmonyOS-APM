# HarmonyOS-APM

HarmonyOS 应用性能监控（Application Performance Monitoring）SDK，基于 ArkTS + C++ 构建，适用于 HarmonyOS Stage 模型应用。

## 功能特性

- **Native Crash 监控** — C++ 信号处理器捕获 SIGSEGV、SIGABRT、SIGFPE、SIGILL、SIGBUS 等崩溃，采用 Crash Delayer 机制（`sigsuspend`）延迟进程退出，配合 HiAppEvent 实现 3 秒内实时上报
- **JS Error 监控** — 通过 `errorManager` 全局捕获未处理异常和 Promise 拒绝，自动落盘并上报
- **AppFreeze 检测** — 监听系统 `APP_FREEZE` 事件，检测主线程卡顿（5s 阈值）
- **缓存与上报管线** — 文件落盘 → AES 加密 → GZIP 压缩 → ZIP 打包 → Token 鉴权上传，支持断网缓存、网络恢复自动补传、指数退避重试
- **零三方依赖** — 纯系统 API 实现，无第三方运行时依赖

## 项目结构

```
apm/                        # 核心 SDK 库 (HSP)
  Index.ets                 # 公开 API: ApmStarter, APMConfig, APMConfigBuilder
  src/main/ets/apm/
    ApmStarter.ets          # SDK 入口
    core/                   # 核心单例，编排所有服务
    config/                 # 配置类型、默认值、Builder、Manager
    services/               # Token、Network、Report、Cache 等服务
    utils/                  # 函数式工具 (withRetry, withLock, withTimeout 等)
    types/                  # 上报/网络/上传类型定义
    platform/               # 平台抽象 (FileSystem, Crypto, NetworkClient, Compression)
    cache/                  # 缓存 save/scan/clean/use
    data_collection/        # 事件监控 (EventChannel, AppMonitor, NativeCrash)
  src/main/cpp/             # Native C++ 崩溃处理器 (NAPI)
entry/                      # Demo 应用 (HAP)
native_error_demo/          # 崩溃模拟器 (HSP)
docs/                       # 架构设计文档
```

## 环境要求

- HarmonyOS SDK 6.0.0(20)
- DevEco Studio 5.x+
- OHPM (OpenHarmony Package Manager)

## 接入 SDK

在 `EntryAbility` 的 `onCreate` 中初始化：

```typescript
import { APMConfigBuilder, ApmStarter } from 'apm';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const context = this.context.getApplicationContext();

    const config = APMConfigBuilder.create(context)
      .setAppVersion('1.0.0')
      .setKeys('<YOUR_AES_KEY>', '<YOUR_AES_IV>')
      .setDebug(true)
      .setProductName('MyApp')
      .setUserIdFunc(() => this.userId)
      .build();

    ApmStarter.start(this.context, config);
  }
}
```


## 几个有意思的设计点

1. 双线程初始化：主线程跑缓存清理/上传/网络监听/JS 错误捕获；worker 线程（@Concurrent）跑 AppFreeze + 原生崩溃监控。因为 taskpool worker 不共享堆，所以每个线程各自构造一个 APMCore 单例。
2. 崩溃延迟器（Crash Delayer）：原生崩溃最难处理——进程都要挂了怎么还能上报？它在信号处理器里用 sigsuspend 把进程"吊住"，等 ArkTS 层把崩溃数据存盘/上传完，再用 SIGUSR2 通知放行，3 秒超时兜底。
3. 离线兜底：错误总是先落盘，没网时上传失败也没关系，等网络恢复时由扫描服务（CacheScanUploadService）自动补传。

## 文档

- [崩溃处理架构设计](docs/apm_crash_handling_architecture.md)
- [AppFreeze 监控设计](docs/appfreeze_monitoring_design.md)
- [Native Crash 信号映射表](docs/native_crash_signal_mapping.md)
