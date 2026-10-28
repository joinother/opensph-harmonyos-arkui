/*
 * 视频导出：native（wx）侧无法直接调用鸿蒙文档选择器，
 * 因此在沙箱 videos/ 下留一个 export-request.txt（内容为文件名），
 * 这里轮询到后弹出系统保存对话框并把视频复制到用户选择的位置。
 */
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import common from '@ohos.app.ability.common';
import promptAction from '@ohos.promptAction';
import hilog from '@ohos.hilog';

const LOG_TAG = 'OpenSPH';
const VIDEOS_DIR = 'videos';
const REQUEST_FILE = 'export-request.txt';

export class VideoExportWatcher {
  private context: common.UIAbilityContext;
  private timer: number = -1;
  private busy: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  start(): void {
    if (this.timer >= 0) {
      return;
    }
    this.timer = setInterval(() => {
      this.tick();
    }, 1000);
    hilog.info(0x0000, LOG_TAG, 'video export watcher started');
  }

  stop(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private async tick(): Promise<void> {
    if (this.busy) {
      return;
    }
    const dir: string = `${this.context.filesDir}/${VIDEOS_DIR}`;
    const request: string = `${dir}/${REQUEST_FILE}`;
    if (!fs.accessSync(request)) {
      return;
    }
    let name: string = '';
    try {
      name = fs.readTextSync(request).trim();
    } catch (e) {
      hilog.error(0x0000, LOG_TAG, 'read export request failed: %{public}s', JSON.stringify(e));
    }
    try {
      fs.unlinkSync(request);
    } catch (e) {
      hilog.warn(0x0000, LOG_TAG, 'remove export request failed: %{public}s', JSON.stringify(e));
    }
    const source: string = `${dir}/${name}`;
    if (name.length === 0 || !fs.accessSync(source)) {
      return;
    }
    this.busy = true;
    let destination: fs.File | undefined = undefined;
    try {
      const view: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.context);
      const options: picker.DocumentSaveOptions = {
        newFileNames: [name],
        fileSuffixChoices: ['MP4 视频|.mp4']
      };
      const uris: string[] = await view.save(options);
      if (uris.length === 0) {
        promptAction.showToast({ message: '已取消导出，视频保留在应用内' });
        return;
      }
      destination = await fs.open(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.copyFile(source, destination.fd);
      await fs.fsync(destination.fd);
      promptAction.showToast({ message: `视频已保存：${name}` });
      hilog.info(0x0000, LOG_TAG, 'video exported: %{public}s', uris[0]);
    } catch (e) {
      hilog.error(0x0000, LOG_TAG, 'video export failed: %{public}s', JSON.stringify(e));
      promptAction.showToast({ message: '导出失败：' + JSON.stringify(e) });
    } finally {
      if (destination) {
        fs.closeSync(destination);
      }
      this.busy = false;
    }
  }
}
