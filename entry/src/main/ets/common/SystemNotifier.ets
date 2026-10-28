// 系统通知（后台/长任务可见）：模拟完成、视频导出完成等。
// 首次发布前查询授权，未授权则引导一次；失败只记录，不影响主流程。
import notificationManager from '@ohos.notificationManager';
import hilog from '@ohos.hilog';

const TAG: string = 'OpenSPH-notify';

export class SystemNotifier {
  private static asked: boolean = false;

  static async ensureEnabled(): Promise<boolean> {
    try {
      const enabled: boolean = await notificationManager.isNotificationEnabled();
      if (enabled) {
        return true;
      }
      if (!SystemNotifier.asked) {
        SystemNotifier.asked = true;
        await notificationManager.requestEnableNotification();
        return await notificationManager.isNotificationEnabled();
      }
      return false;
    } catch (e) {
      hilog.warn(0x0000, TAG, 'ensureEnabled failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  static async publish(id: number, title: string, text: string): Promise<void> {
    const ok: boolean = await SystemNotifier.ensureEnabled();
    if (!ok) {
      hilog.info(0x0000, TAG, 'notifications disabled, skip: %{public}s', title);
      return;
    }
    try {
      const request: notificationManager.NotificationRequest = {
        id: id,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text
          }
        }
      };
      await notificationManager.publish(request);
    } catch (e) {
      hilog.warn(0x0000, TAG, 'publish failed: %{public}s', JSON.stringify(e));
    }
  }
}
