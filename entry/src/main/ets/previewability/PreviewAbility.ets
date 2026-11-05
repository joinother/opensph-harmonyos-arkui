import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import hilog from '@ohos.hilog';
import { CursorUtil } from '../common/CursorUtil';

/**
 * 独立预览窗口 Ability。
 *
 * 用独立 UIAbility（而不是 createSubWindow）才能：
 *  - 在任务栏 / 多任务视图中作为独立窗口出现；
 *  - 被单独最小化、最大化、切换；
 *  - 关闭时不影响主窗口。
 */
export default class PreviewAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(0x0000, 'OpenSPHPreviewAbility', 'onWindowStageCreate');
    try {
      const win: window.Window = windowStage.getMainWindowSync();
      CursorUtil.setWindowId(win.getWindowProperties().id);
      win.setWindowDecorVisible(true);
      win.setWindowTitleButtonVisible(true, true, true);
      win.setWindowDecorHeight(40);
      win.setWindowBackgroundColor('#1b1d21');
    } catch (e) {
      hilog.warn(0x0000, 'OpenSPHPreviewAbility', `window setup failed: ${String(e)}`);
    }
    windowStage.loadContent('pages/PreviewWindow');
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'OpenSPHPreviewAbility', 'onWindowStageDestroy');
  }
}
