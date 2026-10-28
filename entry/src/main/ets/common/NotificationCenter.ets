// 应用内通知中心：状态变化提示（轻量 toast + 历史），供各页面订阅。
// 动效规范：入场 220ms EaseOut（上滑+淡入），出场 180ms EaseIn（淡出），最多同时 4 条。

export enum NoticeLevel {
  INFO = 0,
  SUCCESS = 1,
  WARN = 2,
  ERROR = 3
}

export class AppNotice {
  id: number;
  level: NoticeLevel;
  title: string;
  message: string;
  stamp: string;

  constructor(id: number, level: NoticeLevel, title: string, message: string, stamp: string) {
    this.id = id;
    this.level = level;
    this.title = title;
    this.message = message;
    this.stamp = stamp;
  }
}

type NoticeListener = (notice: AppNotice) => void;

export class NoticeService {
  private static shared: NoticeService | null = null;
  private listeners: NoticeListener[] = [];
  private seq: number = 1;

  static get(): NoticeService {
    if (NoticeService.shared === null) {
      NoticeService.shared = new NoticeService();
    }
    return NoticeService.shared!;
  }

  subscribe(listener: NoticeListener): void {
    this.listeners.push(listener);
  }

  unsubscribe(listener: NoticeListener): void {
    this.listeners = this.listeners.filter((l: NoticeListener) => l !== listener);
  }

  push(level: NoticeLevel, title: string, message: string): void {
    const now: Date = new Date();
    const stamp: string =
      `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now
        .getSeconds()
        .toString()
        .padStart(2, '0')}`;
    const notice: AppNotice = new AppNotice(this.seq, level, title, message, stamp);
    this.seq += 1;
    for (const listener of this.listeners) {
      listener(notice);
    }
  }

  info(title: string, message: string): void {
    this.push(NoticeLevel.INFO, title, message);
  }

  success(title: string, message: string): void {
    this.push(NoticeLevel.SUCCESS, title, message);
  }

  warn(title: string, message: string): void {
    this.push(NoticeLevel.WARN, title, message);
  }

  error(title: string, message: string): void {
    this.push(NoticeLevel.ERROR, title, message);
  }
}
