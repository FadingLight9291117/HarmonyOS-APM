import router from '@ohos.router';

@Entry
@Component
struct DetailPage {
  @State params: string = '';

  aboutToAppear() {
    // 获取传递的参数
    const routerParams = router.getParams() as Record<string, string>;
    if (routerParams) {
      this.params = routerParams['message'] || '无参数';
    }
  }

  build() {
    Column() {
      Text('详情页面')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 40, bottom: 20 })

      Text(`接收到的参数: ${this.params}`)
        .fontSize(16)
        .margin({ top: 20, bottom: 40 })

      Button('返回首页')
        .width('80%')
        .backgroundColor('#007DFF')
        .onClick(() => {
          router.back();
        })

      Button('跳转到设置页')
        .width('80%')
        .backgroundColor('#36D1DC')
        .margin({ top: 20 })
        .onClick(() => {
          router.pushUrl({
            url: 'pages/SettingsPage',
            params: {
              from: 'DetailPage'
            }
          });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
