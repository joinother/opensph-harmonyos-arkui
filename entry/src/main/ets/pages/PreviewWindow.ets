import window from '@ohos.window';
import hilog from '@ohos.hilog';
import image from '@ohos.multimedia.image';
import ark from 'libopensph_ark.so';
import { WindowHolder } from '../common/WindowHolder';

// 独立预览子窗口：直接使用内核侧的 C++ 光栅化（renderSplat），
// 与主窗口预览同一套着色代码，不再维护第二份 Canvas 绘制实现。
@Entry
@Component
struct PreviewWindow {
  @State private pix: image.PixelMap | null = null;
  @State private status: string = '等待数据';
  private yaw: number = 0.7;
  private pitch: number = 0.45;
  private busy: boolean = false;
  private lastX: number = 0;
  private lastY: number = 0;
  private timer: number = -1;
  private pixW: number = 0;
  private pixH: number = 0;

  aboutToAppear(): void {
    this.refresh(true);
    // 模拟运行时定期刷新，静止时只在交互后重绘
    this.timer = setInterval(() => {
      if (!this.refreshFromExport()) {
        this.refresh(false);
      }
    }, 500);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  // 渲染导出进行中时，优先显示导出线程刚渲染的那一帧（真正的实时状态）
  private refreshFromExport(): boolean {
    try {
      interface SimStatus {
        active: boolean;
        rendered: number;
        total: number;
      }
      const st: SimStatus = JSON.parse(String(ark.simExportStatus())) as SimStatus;
      if (!st.active) {
        return false;
      }
      const ab: ArrayBuffer = ark.simExportPreview() as ArrayBuffer;
      if (ab === null || ab.byteLength !== 480 * 270 * 4) {
        return false;
      }
      const opts: image.InitializationOptions = {
        size: { width: 480, height: 270 },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: false
      };
      this.pix = image.createPixelMapSync(ab, opts);
      this.status = `模拟渲染 ${st.rendered} / ${st.total} 帧`;
      return true;
    } catch (e) {
      return false;
    }
  }

  private async refresh(force: boolean): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const handle: number = WindowHolder.previewHandle;
      if (handle < 0) {
        this.status = '主窗口没有选中节点';
        this.busy = false;
        return;
      }
      const W: number = 720;
      const H: number = 520;
      const buf: ArrayBuffer = ark.renderSplat(handle, this.yaw, this.pitch, W, H) as ArrayBuffer;
      if (buf === undefined || buf === null || buf.byteLength !== W * H * 4) {
        this.status = '该节点暂无几何可渲染';
        this.busy = false;
        return;
      }
      const opts: image.InitializationOptions = {
        size: { width: W, height: H },
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      };
      let pm: image.PixelMap | null = this.pix;
      if (pm === null || this.pixW !== W || this.pixH !== H) {
        pm = await image.createPixelMap(buf, opts);
        this.pixW = W;
        this.pixH = H;
      } else {
        await pm.writeBufferToPixels(buf);
      }
      this.pix = pm;
      this.status = force ? '已就绪' : '实时';
    } catch (e) {
      const err = e as Error;
      hilog.error(0x0000, 'OpenSPHWin', `sub preview failed: ${err.message ?? String(e)}`);
      this.status = '渲染失败';
    }
    this.busy = false;
  }

  private async closeSelf(): Promise<void> {
    try {
      const sub: window.Window | null = WindowHolder.sub;
      if (sub !== null) {
        await sub.destroyWindow();
        WindowHolder.sub = null;
      }
    } catch (e) {
      hilog.warn(0x0000, 'OpenSPHWin', 'destroy sub window failed');
    }
  }

  build() {
    Column() {
      // 标题与关闭由系统窗口栏提供，这里只留一行状态（不再重复画标题和关闭按钮）
      Row() {
        Text(this.status).fontSize(11).fontColor('#8b929b');
        Blank();
        Text('拖动旋转 · 滚轮/双指缩放').fontSize(10).fontColor('#b0b6be');
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 });

      if (this.pix !== null) {
        Image(this.pix)
          .width('100%')
          .layoutWeight(1)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.Medium)
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.All, distance: 0 })
              .onActionStart(() => {
                this.lastX = 0;
                this.lastY = 0;
              })
              .onActionUpdate((event: GestureEvent) => {
                const dx: number = event.offsetX - this.lastX;
                const dy: number = event.offsetY - this.lastY;
                this.lastX = event.offsetX;
                this.lastY = event.offsetY;
                this.yaw += dx * 0.01;
                this.pitch = Math.max(-1.5, Math.min(1.5, this.pitch + dy * 0.01));
                this.refresh(false);
              })
          )
      } else {
        Column() {
          Text('暂无预览').fontSize(13).fontColor('#5f6670');
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#0b0f14');
  }
}
