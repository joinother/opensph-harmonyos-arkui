import pointer from '@ohos.multimodalInput.pointer';
import window from '@ohos.window';
import hilog from '@ohos.hilog';

/**
 * 鼠标指针样式适配。
 *
 * 鸿蒙没有 CSS cursor，只能用 pointer.setPointerStyle(windowId, style)，
 * 因此需要按组件的 onHover 事件切换、离开时复位为 DEFAULT。
 * windowId 在 Ability 启动时拿到并存进 WindowHolder，这里直接取。
 */
export class CursorUtil {
  private static winId: number = -1;
  private static enabled: boolean = true;

  public static setWindowId(id: number): void {
    CursorUtil.winId = id;
    hilog.info(0x0000, 'OpenSPHCursor', `windowId=${id}`);
  }

  public static isAvailable(): boolean {
    return CursorUtil.enabled && CursorUtil.winId >= 0;
  }

  private static lastStyle: number = -1;

  public static apply(style: pointer.PointerStyle): void {
    if (!CursorUtil.isAvailable()) {
      return;
    }
    if (CursorUtil.lastStyle !== style) {
      CursorUtil.lastStyle = style;
      hilog.info(0x0000, 'OpenSPHCursor', `apply style=${style}`);
    }
    try {
      pointer.setPointerStyle(CursorUtil.winId, style).catch((e: Object) => {
        // 某些窗口/场景下不支持，只记录一次，避免刷屏
        CursorUtil.enabled = false;
        hilog.warn(0x0000, 'OpenSPHCursor', `setPointerStyle failed: ${JSON.stringify(e)}`);
      });
    } catch (e) {
      CursorUtil.enabled = false;
      hilog.warn(0x0000, 'OpenSPHCursor', `setPointerStyle threw: ${String(e)}`);
    }
  }

  public static reset(): void {
    CursorUtil.apply(pointer.PointerStyle.DEFAULT);
  }

  // ---- 语义化包装：各处只调这些，避免散落的枚举 ----
  /** 可点击（按钮/菜单项/标签/开关/下拉） */
  public static hand(): void {
    CursorUtil.apply(pointer.PointerStyle.HAND_POINTING);
  }
  /** 可拖拽移动（节点卡片） */
  public static move(): void {
    CursorUtil.apply(pointer.PointerStyle.MOVE);
  }
  /** 画布可平移（未按下） */
  public static grab(): void {
    CursorUtil.apply(pointer.PointerStyle.HAND_OPEN);
  }
  /** 画布平移中（已按下） */
  public static grabbing(): void {
    CursorUtil.apply(pointer.PointerStyle.HAND_GRABBING);
  }
  /** 输出端口：可拖出连线 */
  public static link(): void {
    CursorUtil.apply(pointer.PointerStyle.CROSS);
  }
  /** 输入端口：可接收连线 */
  public static dropTarget(): void {
    CursorUtil.apply(pointer.PointerStyle.CURSOR_COPY);
  }
  /** 左右分隔条 */
  public static resizeH(): void {
    CursorUtil.apply(pointer.PointerStyle.RESIZE_LEFT_RIGHT);
  }
  /** 上下分隔条 */
  public static resizeV(): void {
    CursorUtil.apply(pointer.PointerStyle.RESIZE_UP_DOWN);
  }
  /** 文本输入 */
  public static text(): void {
    CursorUtil.apply(pointer.PointerStyle.TEXT_CURSOR);
  }
  /** 禁止操作 */
  public static forbid(): void {
    CursorUtil.apply(pointer.PointerStyle.CURSOR_FORBID);
  }
}
