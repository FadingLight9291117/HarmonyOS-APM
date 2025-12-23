import router from '@ohos.router';

@Entry
@Component
struct SettingsPage {
  @State fromPage: string = '';
  @State switchValue: boolean = false;

  aboutToAppear() {
    const routerParams = router.getParams() as Record<string, string>;
    if (routerParams) {
      this.fromPage = routerParams['from'] || '未知';
    }
  }

  build() {
    Column() {
      Text('设置页面')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 40, bottom: 20 })

      Text(`来自: ${this.fromPage}`)
        .fontSize(14)
        .fontColor('#666')
        .margin({ bottom: 30 })

      Column({ space: 15 }) {
        Row() {
          Text('开启通知')
            .fontSize(16)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.switchValue })
            .onChange((isOn: boolean) => {
              this.switchValue = isOn;
            })
        }
        .width('80%')
        .padding(10)

        Row() {
          Text('自动更新')
            .fontSize(16)
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: false })
        }
        .width('80%')
        .padding(10)
      }

      Button('返回')
        .width('80%')
        .backgroundColor('#007DFF')
        .margin({ top: 40 })
        .onClick(() => {
          router.back();
        })

      Button('返回首页')
        .width('80%')
        .backgroundColor('#FF6B6B')
        .margin({ top: 20 })
        .onClick(() => {
          router.clear();
          router.pushUrl({ url: 'pages/Index' });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
