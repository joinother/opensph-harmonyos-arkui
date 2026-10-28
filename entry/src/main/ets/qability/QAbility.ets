import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import QAbilityStage from '../qabilitystage/QAbilityStage';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import Window from '@ohos.window'
import hilog from '@ohos.hilog';
import { BusinessError } from '@ohos.base';
import { fileIo as fs } from '@kit.CoreFileKit';
import qpa from 'libqohos.so';
import {LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';
import { VideoExportWatcher } from '../common/VideoExport';

export default class QAbility extends UIAbility {

  private localStorage: LocalStorage | null = null;

  // 视频导出看门狗：native(wx) 侧渲染完视频后写 videos/export-request.txt，
  // 这里轮询到就弹系统保存框，把沙箱里的 mp4 复制到用户选的位置。
  private exportWatcher: VideoExportWatcher | null = null;

  // 把 rawfile 里的 OpenSPH.mo 国际化词库拷贝到应用沙箱 filesDir 根目录。
  // （wxFileTranslationsLoader 需要 <prefix>/<lang>/LC_MESSAGES 子目录，这些
  // 由 native 侧 OpenSPH 启动时用 POSIX mkdir 复制补齐。）
  private _catalogBuf: Uint8Array = new Uint8Array(0);

  // 把 rawfile 里的演示 session（CLI 用）拷贝到沙箱 filesDir，native CLI
  // 即可 headless 运行：-p <filesDir>/demo.sph -n simulation
  private async copyCliSessions(): Promise<void> {
    try {
      const ctx = this.context;
      const rm = ctx.resourceManager;
      const names = ['demo.sph', 'moon_earth.sph'];
      for (const name of names) {
        const buf = await rm.getRawFileContent(name);
        const dest = `${ctx.filesDir}/${name}`;
        const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(file.fd, buf.buffer as ArrayBuffer);
        fs.closeSync(file);
        hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: copied rawfile %{public}s (%{public}d bytes)', name, buf.byteLength);
      }
    } catch (e) {
      const be = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility: copy cli sessions failed: code=%{public}d msg=%{public}s', be.code, be.message);
    }
  }

  async copyI18nCatalogs(): Promise<void> {
    try {
      const ctx = this.context;
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: filesDir=%{public}s', ctx.filesDir);
      const rm = ctx.resourceManager;
      this._catalogBuf = await rm.getRawFileContent('OpenSPH.mo');
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: rawfile OpenSPH.mo size=%{public}d', this._catalogBuf.byteLength);
      const dest = `${ctx.filesDir}/OpenSPH.mo`;
      const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, this._catalogBuf.buffer as ArrayBuffer);
      fs.closeSync(file);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: copied OpenSPH.mo (%{public}d bytes) to %{public}s', this._catalogBuf.byteLength, dest);
    } catch (e) {
      const be = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility: copy i18n catalog failed: code=%{public}d msg=%{public}s', be.code, be.message);
    }
  }

  // 把启动参数里的 CLI 命令写入沙箱 arg 文件。native OpenSPH 启动时检测到
  // 该文件（或 OSPH_CLI_ARGS 环境变量）即进入 headless 命令行模式。
  // 结构化解构 want.parameters（避免命令行空格/引号问题）：
  //   --ps cli 1 --ps project <session.sph> --ps node <nodeName>
  // 也兼容 --ps cli "<完整命令>"（含空格需正确引号）。
  private setupCliArgs(want: Want): void {
    try {
      const params = want.parameters as Record<string, Object>;
      const cliOn = params?.['cli'];
      if (cliOn === undefined || cliOn === null || String(cliOn) === '0' || String(cliOn) === 'false') {
        return;
      }
      let cmd = '';
      const project = params?.['project'];
      const node = params?.['node'];
      if (project !== undefined && project !== null && String(project).length > 0) {
        cmd += ` -p ${String(project)}`;
      }
      if (node !== undefined && node !== null && String(node).length > 0) {
        cmd += ` -n ${String(node)}`;
      }
      if (cmd.trim().length === 0) {
        // 兼容直接传整条命令字符串
        cmd = String(cliOn);
      }
      if (cmd.trim().length === 0) {
        return;
      }
      const ctx = this.context;
      const dest = `${ctx.filesDir}/opensph_cli.txt`;
      const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, cmd);
      fs.closeSync(file);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: cli args written: %{public}s', cmd);
    } catch (e) {
      const be = e as BusinessError;
      hilog.error(LOG_DOMAIN, LOG_TAG, 'QAbility: setup cli args failed: code=%{public}d msg=%{public}s', be.code, be.message);
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onCreate(): want.parameters: ' + JSON.stringify(want.parameters));
    QAbilityStage.initQtAppContextIfNeeded(this.context.getApplicationContext());
    // 尽早部署 i18n 词库，OpenSPH native 侧会轮询等待其就绪
    this.copyI18nCatalogs();
    // 部署 CLI 演示 session 文件（headless 模式使用）
    this.copyCliSessions();
    // 部署 CLI 命令行参数（headless 模式入口）
    this.setupCliArgs(want);
    qpa.handleAbilityOnCreate(this, want, launchParam);
  }

  onDestroy(): void | Promise<void> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onDestroy()');
    return qpa.handleAbilityOnDestroy(this);
  }

  onPrepareToTerminate(): boolean {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminate()');
    return qpa.handleAbilityOnPrepareToTerminate(this);
  }

  onPrepareToTerminateAsync(): Promise<boolean> {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onPrepareToTerminateAsync()');
    return qpa.handleAbilityOnPrepareToTerminateAsync(this);
  }

  onWindowStageCreate(windowStage: Window.WindowStage) {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onWindowStageCreate(): this.launchWant.parameters: ' + JSON.stringify(this.launchWant.parameters));
    // 先把系统窗口最大化，再让 Qt/wx 建内容窗口：否则窗口先以默认小尺寸出现、
    // 随后被 wx 的 Maximize 拉大，启动瞬间会“跳一下”。
    try {
      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.maximize().then(() => {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility: main window maximized');
      }).catch((err: BusinessError) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'QAbility: maximize failed: code=%{public}d msg=%{public}s', err.code, err.message);
      });
    } catch (e) {
      const be = e as BusinessError;
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'QAbility: maximize threw: code=%{public}d msg=%{public}s', be.code, be.message);
    }
    if (!this.exportWatcher) {
      this.exportWatcher = new VideoExportWatcher(this.context);
      this.exportWatcher.start();
    }
    qpa.handleAbilityOnWindowStageCreate(this, windowStage);
  }

  onWindowStageRestore(windowStage: Window.WindowStage): void {
    qpa.handleAbilityOnWindowStageRestore(this, windowStage);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onNewWant(): want.parameters: ' + JSON.stringify(want.parameters));
    qpa.handleAbilityOnNewWant(this, want, launchParam);
  }

  onForeground() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onForeground()');
    qpa.handleAbilityOnForeground(this);
  }

  onBackground() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onBackground()');
    qpa.handleAbilityOnBackground(this);
  }

  onWindowStageDestroy() {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'QAbility::onStageDestroy()');
    qpa.handleAbilityOnWindowStageDestroy(this);
  }

  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult | Promise<AbilityConstant.OnContinueResult> {
    return qpa.handleAbilityOnContinue(this, wantParam);
  }
}
