import promptAction from '@ohos.promptAction';

// NAPI 桥接库 - 启动 OpenSPH
import opensphNapi from 'libopensoh_bridge.so';

@Entry
@Component
struct Index {
  @State message: string = 'OpenSPH for HarmonyOS';
  @State status: string = 'Ready';
  @State isRunning: boolean = false;

  build() {
    Column() {
      // 标题
      Text(this.message)
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 60, bottom: 10 })

      Text('SPH/N-body Simulation Suite')
        .fontSize(16)
        .fontColor('#666666')
        .margin({ bottom: 40 })

      // 状态卡片
      Column() {
        Text('运行状态')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ bottom: 8 })
        Text(this.status)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isRunning ? '#00C853' : '#2196F3')
      }
      .width('85%')
      .padding(24)
      .backgroundColor('#F5F5F5')
      .borderRadius(12)
      .margin({ bottom: 30 })

      // 信息列表
      Column() {
        InfoRow({ label: '架构', value: 'ARM64 (aarch64)' })
        InfoRow({ label: 'GUI 框架', value: 'wxWidgets 3.3.2 (Qt backend)' })
        InfoRow({ label: 'Qt 版本', value: '6.12.0 (Qt-OH)' })
        InfoRow({ label: '渲染方式', value: 'Software rasterizer' })
      }
      .width('85%')
      .margin({ bottom: 40 })

      // 启动按钮
      Button(this.isRunning ? '运行中...' : '启动 OpenSPH')
        .width('85%')
        .height(56)
        .fontSize(18)
        .backgroundColor(this.isRunning ? '#BDBDBD' : '#2196F3')
        .enabled(!this.isRunning)
        .onClick(() => {
          this.launchOpenSPH();
        })

      Text('版本 0.4.1-ohos | wxQT + Qt-OH 双层桥接')
        .fontSize(12)
        .fontColor('#999999')
        .margin({ top: 30, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }

  async launchOpenSPH() {
    try {
      this.status = '正在启动...';
      this.isRunning = true;

      // 通过 NAPI 启动 OpenSPH（返回 0=成功，正数=已在运行，字符串=错误信息）
      const result: number | string = opensphNapi.startOpenSPH();

      if (typeof result === 'number') {
        if (result === 0) {
          this.status = '运行中';
          promptAction.showToast({ message: 'OpenSPH 已启动' });
        } else {
          this.status = '已在运行';
        }
      } else {
        // 返回了错误描述字符串
        this.status = '启动失败';
        this.isRunning = false;
        promptAction.showToast({ message: '启动失败: ' + result });
      }
    } catch (err) {
      this.status = '错误: ' + JSON.stringify(err);
      this.isRunning = false;
      promptAction.showToast({ message: '启动失败: ' + JSON.stringify(err) });
    }
  }
}

@Component
struct InfoRow {
  label: string = '';
  value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor('#666666')
        .width(100)
      Text(this.value)
        .fontSize(14)
        .fontColor('#333333')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }
}
