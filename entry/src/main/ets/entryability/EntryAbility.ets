import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { BusinessError } from '@ohos.base';
import { fileIo as fs } from '@kit.CoreFileKit';
import testNapi from 'libopensoh_bridge.so';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    hilog.info(0x0000, 'OpenSPH', '%{public}s', 'Ability onCreate');
  }

  onDestroy() {
    hilog.info(0x0000, 'OpenSPH', '%{public}s', 'Ability onDestroy');
  }

  // 把 rawfile 里的 OpenSPH.mo 国际化词库拷贝到应用沙箱 filesDir，
  // 供 native 侧 wxLocale/wxGetTranslation 加载（OSPH_LANG_DIR 指向 filesDir）。
  async copyI18nCatalogs(): Promise<void> {
    try {
      const ctx = this.context;
      const rm = ctx.resourceManager;
      const buf: Uint8Array = await rm.getRawFileContent('OpenSPH.mo');
      const dest: string = `${ctx.filesDir}/OpenSPH.mo`;
      const file = fs.openSync(dest, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, buf);
      fs.closeSync(file);
      hilog.info(0x0000, 'OpenSPH', 'copied OpenSPH.mo (%{public}d bytes) to %{public}s', buf.byteLength, dest);
    } catch (e) {
      hilog.error(0x0000, 'OpenSPH', 'copy i18n catalog failed: %{public}s', JSON.stringify(e));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    hilog.info(0x0000, 'OpenSPH', '%{public}s', 'onWindowStageCreate');

    // 加载启动页面
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(0x0000, 'OpenSPH', 'Failed to load content. Cause: %{public}s', JSON.stringify(err) ?? '');
        return;
      }
      hilog.info(0x0000, 'OpenSPH', 'Succeeded in loading content.');

      // 先部署 i18n 词库，再启动 OpenSPH（窗口创建后通过 dlopen 运行）
      this.copyI18nCatalogs().then(() => {
        try {
          let result: number | string = testNapi.startOpenSPH();
          hilog.info(0x0000, 'OpenSPH', 'startOpenSPH result: %{public}s', JSON.stringify(result));
        } catch (e) {
          let err = e as BusinessError;
          hilog.error(0x0000, 'OpenSPH', 'startOpenSPH error: %{public}s', JSON.stringify(err) ?? '');
        }
      });
    });
  }

  onWindowStageDestroy() {
    hilog.info(0x0000, 'OpenSPH', '%{public}s', 'onWindowStageDestroy');
  }

  onForeground() {
    hilog.info(0x0000, 'OpenSPH', '%{public}s', 'onForeground');
  }

  onBackground() {
    hilog.info(0x0000, 'OpenSPH', '%{public}s', 'onBackground');
  }
}
