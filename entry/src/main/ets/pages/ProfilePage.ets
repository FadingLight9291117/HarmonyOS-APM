import router from '@ohos.router';

@Entry
@Component
struct ProfilePage {
  @State userName: string = 'OpenHarmony User';
  @State userEmail: string = 'user@example.com';

  aboutToAppear(): void {
    throw Error('test JsError in aboutToAppear');
  }

  build() {
    Column() {
      Text('个人中心')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 40, bottom: 40 })

      // 头像
      Image($r('app.media.app_icon'))
        .width(100)
        .height(100)
        .borderRadius(50)
        .margin({ bottom: 20 })

      Text(this.userName)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .margin({ bottom: 10 })

      Text(this.userEmail)
        .fontSize(14)
        .fontColor('#666')
        .margin({ bottom: 40 })

      // 菜单项
      Column({ space: 15 }) {
        this.menuItem('我的订单', () => {
          router.pushUrl({
            url: 'pages/DetailPage',
            params: { message: '订单列表' }
          });
        })

        this.menuItem('账号设置', () => {
          router.pushUrl({
            url: 'pages/SettingsPage',
            params: { from: 'ProfilePage' }
          });
        })

        this.menuItem('关于我们', () => {
          router.pushUrl({
            url: 'pages/DetailPage',
            params: { message: '关于应用信息' }
          });
        })
      }
      .width('90%')

      Button('返回首页')
        .width('80%')
        .backgroundColor('#007DFF')
        .margin({ top: 50 })
        .onClick(() => {
          router.back();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }

  @Builder menuItem(title: string, onClick: () => void) {
    Row() {
      Text(title)
        .fontSize(16)
      Blank()
      Text('>')
        .fontSize(16)
        .fontColor('#999')
    }
    .width('100%')
    .padding(15)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .onClick(onClick)
  }
}
