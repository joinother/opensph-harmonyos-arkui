import UIAbility from '@ohos.app.ability.UIAbility';
import Window from '@ohos.window';
import hilog from '@ohos.hilog';
import { WindowHolder } from '../common/WindowHolder';

export default class ArkAbility extends UIAbility {
  onWindowStageCreate(windowStage: Window.WindowStage): void {
    hilog.info(0x0000, 'OpenSPH', 'ArkAbility: onWindowStageCreate');
    try {
      WindowHolder.stage = windowStage;
      windowStage.getMainWindowSync().maximize();
    } catch (e) {
      hilog.warn(0x0000, 'OpenSPH', 'ArkAbility: window setup failed');
    }
    windowStage.loadContent('pages/ArkMain');
  }
}
