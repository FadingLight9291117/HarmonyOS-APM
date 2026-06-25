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

## 快速开始

### 安装依赖

```bash
ohpm install
```

### 接入 SDK

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

### APMConfigBuilder API

| 方法 | 说明 | 必填 |
|------|------|------|
| `setAppVersion(version)` | 应用版本 | 是 |
| `setAppType(type)` | 客户端类型 | 是 |
| `setChannel(channel)` | 渠道 | 是 |
| `setKeys(keyHex, iv)` | AES 加密密钥和 IV | 否 |
| `setDebug(isDebug)` | 调试模式 | 否 |
| `setProductName(name)` | 产品名称 | 否 |
| `setBuildId(id)` | 构建 ID | 否 |
| `setDeviceId(id)` | 设备 ID | 否 |
| `setBranchName(name)` | Git 分支 | 否 |
| `setCommitRevision(rev)` | Git 提交版本 | 否 |
| `setKernelVersion(ver)` | 内核版本 | 否 |
| `setBundleName(name)` | 包名 | 否 |
| `setLogBackend(backend)` | 自定义日志后端 | 否 |
| `setExtraInfo(info)` | 自定义扩展字段 | 否 |
| `setUserIdFunc(func)` | 动态获取用户 ID（仅主线程有效，不跨 Worker 边界） | 否 |

## 构建

```bash
hvigorw assembleHap       # 构建 Demo 应用 (HAP)
hvigorw assembleHsp       # 构建 SDK 共享包 (HSP)
hvigorw clean             # 清理构建产物
```

## 测试

测试框架：`@ohos/hypium` + `@ohos/hamock`

```bash
# 单元测试
hvigorw --mode module -p module=apm@default test

# 设备测试
hvigorw --mode module -p module=apm@default ohosTest
```

运行单个测试：在对应模块的 `List.test.ets` 中仅导入目标测试文件，或在测试文件中使用 `describe.only` / `it.only`。

## 代码检查

```bash
hvigorw lint
```

规则集：`@performance/recommended`、`@typescript-eslint/recommended`，以及全部 `@security/no-unsafe-*` 安全规则（均为 error 级别）。

## 技术架构

### 双线程初始化

SDK 启动时在两个线程上独立完成初始化，这是最重要的架构事实：

```
主线程 (Main Thread)
  └─ APMCore.init()
       ├─ startCacheServices()   # 缓存清理 / 离线补传
       ├─ startNetConService()   # 网络恢复监听
       └─ JS 错误捕获            # errorManager.on('globalErrorOccurred' / 'globalUnhandledRejectionDetected')

Worker 线程 (@Concurrent via taskpool)
  └─ APMCore.init()              # 独立的第二个单例
       └─ startMonitorServices() # AppFreeze + Native Crash 监控
```

因为 `taskpool` Worker 不共享堆，**每个线程各自持有一个独立的 `APMCore` 单例**。跨线程的 config 参数会先经过 `filterConfig()` 过滤，移除无法序列化的函数类型字段（如 `setUserIdFunc` 配置的回调），因此该回调只在主线程侧生效。

### Native Crash 处理流程

```
信号触发 (SIGSEGV等)
  → C++ 信号处理器捕获
  → Crash Delayer (sigsuspend 挂起进程)
  → HiAppEvent IPC 回调通知 ArkTS 层
  → ArkTS 落盘 + 上报
  → SIGUSR2 通知 C++ 层处理完成
  → 进程退出（3s 超时保护）
```

### 上报管线与离线兜底

所有错误**总是先落盘**，上传失败（无论是断网还是服务端异常）不会丢数据。网络恢复时，`CacheScanUploadService` 自动扫描磁盘缓存补传，上传失败按指数退避重试。

```
事件采集
  → 文件落盘（CacheService）
  → AES-256-CBC 加密 + GZIP 压缩（EncryptCompressService）
  → ZIP 打包
  → Token 鉴权
  → 上传（支持分片，失败指数退避重试）
      ↑
      └─ 网络恢复时，CacheScanUploadService 自动补传历史缓存
```

## 文档

- [崩溃处理架构设计](docs/apm_crash_handling_architecture.md)
- [AppFreeze 监控设计](docs/appfreeze_monitoring_design.md)
- [Native Crash 信号映射表](docs/native_crash_signal_mapping.md)

## 许可证

Apache-2.0
