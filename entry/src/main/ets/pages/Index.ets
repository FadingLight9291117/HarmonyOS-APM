import {
  crashNullPointer,
  crashInvalidMemory,
  crashAbort,
  crashDivideByZero,
  crashBusError,
  crashStackOverflow,
  crashIllegalInstruction,
  crashTrap,
  crashInThread,
  crashHeapOverflow,
  crashDoubleFree,
  crashUseAfterFree
} from 'native_error_demo';

@Entry
@Component
struct Index {
  @State message: string = 'Native Crash Demo';

  build() {
    Column() {
      Text(this.message)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 20, bottom: 20 })

      Scroll() {
        Column({ space: 10 }) {
          // SIGSEGV 类
          Text('SIGSEGV (段错误)')
            .fontSize(16)
            .fontColor('#666')
            .width('100%')
            .padding({ left: 16 })

          Button('空指针解引用')
            .width('90%')
            .backgroundColor('#FF6B6B')
            .onClick(() => crashNullPointer())

          Button('非法内存访问')
            .width('90%')
            .backgroundColor('#FF6B6B')
            .onClick(() => crashInvalidMemory())

          Button('栈溢出 (递归)')
            .width('90%')
            .backgroundColor('#FF6B6B')
            .onClick(() => crashStackOverflow())

          // SIGABRT 类
          Text('SIGABRT (中止)')
            .fontSize(16)
            .fontColor('#666')
            .width('100%')
            .padding({ left: 16 })
            .margin({ top: 10 })

          Button('调用 abort()')
            .width('90%')
            .backgroundColor('#FF8C42')
            .onClick(() => crashAbort())

          Button('双重释放 (Double Free)')
            .width('90%')
            .backgroundColor('#FF8C42')
            .onClick(() => crashDoubleFree())

          // SIGFPE 类
          Text('SIGFPE (浮点异常)')
            .fontSize(16)
            .fontColor('#666')
            .width('100%')
            .padding({ left: 16 })
            .margin({ top: 10 })

          Button('整数除以零')
            .width('90%')
            .backgroundColor('#FFD93D')
            .fontColor('#333')
            .onClick(() => crashDivideByZero())

          // SIGBUS 类
          Text('SIGBUS (总线错误)')
            .fontSize(16)
            .fontColor('#666')
            .width('100%')
            .padding({ left: 16 })
            .margin({ top: 10 })

          Button('未对齐内存访问')
            .width('90%')
            .backgroundColor('#6BCB77')
            .onClick(() => crashBusError())

          // SIGILL 类
          Text('SIGILL (非法指令)')
            .fontSize(16)
            .fontColor('#666')
            .width('100%')
            .padding({ left: 16 })
            .margin({ top: 10 })

          Button('非法指令')
            .width('90%')
            .backgroundColor('#4D96FF')
            .onClick(() => crashIllegalInstruction())

          // SIGTRAP 类
          Text('SIGTRAP (陷阱)')
            .fontSize(16)
            .fontColor('#666')
            .width('100%')
            .padding({ left: 16 })
            .margin({ top: 10 })

          Button('断点/陷阱')
            .width('90%')
            .backgroundColor('#9B59B6')
            .onClick(() => crashTrap())

          // 线程崩溃
          Text('线程崩溃')
            .fontSize(16)
            .fontColor('#666')
            .width('100%')
            .padding({ left: 16 })
            .margin({ top: 10 })

          Button('子线程崩溃')
            .width('90%')
            .backgroundColor('#E74C3C')
            .onClick(() => crashInThread())

          // 内存错误
          Text('内存错误')
            .fontSize(16)
            .fontColor('#666')
            .width('100%')
            .padding({ left: 16 })
            .margin({ top: 10 })

          Button('堆缓冲区溢出')
            .width('90%')
            .backgroundColor('#1ABC9C')
            .onClick(() => crashHeapOverflow())

          Button('释放后使用 (UAF)')
            .width('90%')
            .backgroundColor('#1ABC9C')
            .onClick(() => crashUseAfterFree())
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .height('100%')
    .width('100%')
  }
}

@Concurrent
function testNativeCrash() {
}

