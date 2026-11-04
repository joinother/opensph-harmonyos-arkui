import UIAbility from '@ohos.app.ability.UIAbility';
import Window from '@ohos.window';
import hilog from '@ohos.hilog';
import { WindowHolder } from '../common/WindowHolder';
import { CursorUtil } from '../common/CursorUtil';

export default class ArkAbility extends UIAbility {
  onWindowStageCreate(windowStage: Window.WindowStage): void {
    hilog.info(0x0000, 'OpenSPH', 'ArkAbility: onWindowStageCreate');
    try {
      WindowHolder.stage = windowStage;
      const mainWin: Window.Window = windowStage.getMainWindowSync();
      // 记录 windowId，鼠标指针样式必须按窗口设置
      CursorUtil.setWindowId(mainWin.getWindowProperties().id);
      mainWin.maximize();
    } catch (e) {
      hilog.warn(0x0000, 'OpenSPH', 'ArkAbility: window setup failed');
    }
    windowStage.loadContent('pages/ArkMain');
  }
}
