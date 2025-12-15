# Native 崩溃信号映射表

本文档描述了 APM SDK 中 Native 层崩溃捕获所支持的信号类型及其详细原因映射。

## 信号类型概览

| 信号 | 信号值 | 说明 |
|------|--------|------|
| SIGSEGV | 11 | 段错误（非法内存访问） |
| SIGABRT | 6 | 程序中止 |
| SIGFPE | 8 | 浮点异常 |
| SIGILL | 4 | 非法指令 |
| SIGBUS | 7 | 总线错误 |
| SIGTRAP | 5 | 陷阱/断点 |

---

## 详细原因映射

### SIGSEGV（段错误）

| si_code | crash_reason | 说明 |
|---------|--------------|------|
| SEGV_MAPERR | Address not mapped to object | 访问的地址未映射到任何对象 |
| SEGV_ACCERR | Invalid permissions for mapped object | 对映射对象没有访问权限 |
| 其他 | Segmentation fault | 通用段错误 |

**常见场景：**
- 空指针解引用
- 访问已释放的内存
- 数组越界访问
- 栈溢出

---

### SIGABRT（程序中止）

| si_code | crash_reason | 说明 |
|---------|--------------|------|
| - | Process abort signal | 程序中止信号 |

**常见场景：**
- 调用 `abort()` 函数
- `assert()` 断言失败
- C++ 异常未被捕获
- `std::terminate()` 被调用
- 内存分配失败（某些实现）

---

### SIGFPE（浮点异常）

| si_code | crash_reason | 说明 |
|---------|--------------|------|
| FPE_INTDIV | Integer divide by zero | 整数除以零 |
| FPE_INTOVF | Integer overflow | 整数溢出 |
| FPE_FLTDIV | Floating-point divide by zero | 浮点数除以零 |
| FPE_FLTOVF | Floating-point overflow | 浮点数溢出 |
| FPE_FLTUND | Floating-point underflow | 浮点数下溢 |
| FPE_FLTRES | Floating-point inexact result | 浮点数结果不精确 |
| FPE_FLTINV | Invalid floating-point operation | 无效的浮点操作 |
| FPE_FLTSUB | Subscript out of range | 下标越界 |
| 其他 | Floating-point exception | 通用浮点异常 |

**常见场景：**
- 除以零操作
- 数值溢出
- 无效的数学运算（如 sqrt(-1)）

---

### SIGILL（非法指令）

| si_code | crash_reason | 说明 |
|---------|--------------|------|
| ILL_ILLOPC | Illegal opcode | 非法操作码 |
| ILL_ILLOPN | Illegal operand | 非法操作数 |
| ILL_ILLADR | Illegal addressing mode | 非法寻址模式 |
| ILL_ILLTRP | Illegal trap | 非法陷阱 |
| ILL_PRVOPC | Privileged opcode | 特权操作码 |
| ILL_PRVREG | Privileged register | 特权寄存器 |
| ILL_COPROC | Coprocessor error | 协处理器错误 |
| ILL_BADSTK | Internal stack error | 内部栈错误 |
| 其他 | Illegal instruction | 通用非法指令 |

**常见场景：**
- 执行了损坏的代码
- CPU 不支持的指令
- 代码段被意外修改
- 函数指针指向非代码区域

---

### SIGBUS（总线错误）

| si_code | crash_reason | 说明 |
|---------|--------------|------|
| BUS_ADRALN | Invalid address alignment | 无效的地址对齐 |
| BUS_ADRERR | Nonexistent physical address | 物理地址不存在 |
| BUS_OBJERR | Object-specific hardware error | 特定对象的硬件错误 |
| 其他 | Bus error | 通用总线错误 |

**常见场景：**
- 未对齐的内存访问（在要求对齐的架构上）
- 访问不存在的物理内存
- 硬件故障

---

### SIGTRAP（陷阱/断点）

| si_code | crash_reason | 说明 |
|---------|--------------|------|
| TRAP_BRKPT | Process breakpoint | 进程断点 |
| TRAP_TRACE | Process trace trap | 进程跟踪陷阱 |
| 其他 | Trace/breakpoint trap | 通用陷阱/断点 |

**常见场景：**
- 调试器断点
- 单步执行
- 代码中的 `__builtin_trap()`

---

## 崩溃日志格式

```json
{
  "signal": 11,
  "signal_name": "SIGSEGV",
  "pid": 12345,
  "tid": 12345,
  "time": 1702444800000,
  "crash_type": "NativeCrash",
  "crash_name": "SIGSEGV",
  "crash_reason": "Address not mapped to object",
  "fault_addr": "0x0000000000000000",
  "backtrace": [
    "0x12345678 libexample.so!function_name+0x10",
    "0x12345679 libexample.so!caller_function+0x20",
    "..."
  ]
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| signal | number | 信号编号 |
| signal_name | string | 信号名称 |
| pid | number | 进程 ID |
| tid | number | 线程 ID |
| time | number | 崩溃时间戳（毫秒） |
| crash_type | string | 崩溃类型，固定为 "NativeCrash" |
| crash_name | string | 崩溃名称（同 signal_name） |
| crash_reason | string | 崩溃详细原因 |
| fault_addr | string | 故障地址（十六进制，可选） |
| backtrace | string[] | 调用栈信息 |

---

## 文件存储路径

- **崩溃日志文件**: `/data/storage/el2/base/cache/crash_info_{pid}_{timestamp}.json`
- **待上传标志文件**: `/data/storage/el2/base/cache/.crash_pending`

---

## 相关代码

- 信号处理: `apm/src/main/cpp/signal_handler.cpp`
- 崩溃处理入口: `apm/src/main/cpp/crash_handler.cpp`

