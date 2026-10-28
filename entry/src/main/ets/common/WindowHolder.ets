import window from '@ohos.window';

/**
 * 跨页面共享的窗口引用与预览目标：
 * - stage：主窗口的 WindowStage（ArkAbility 写入）
 * - sub：当前弹出的子窗口（预览窗）
 * - previewHandle：主窗口当前想预览的节点 handle（子窗口据此向内核取数据）
 */
export class WindowHolder {
  static stage: window.WindowStage | null = null;
  static sub: window.Window | null = null;
  static previewHandle: number = -1;
}
