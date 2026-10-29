import net from '@ohos.net.socket';
import hilog from '@ohos.hilog';

/**
 * 应用内可控远程接口（默认关闭，需用户在界面开启）。
 *
 * 设计要点：
 * - 双栈监听：IPv4 与 IPv6 各起一个 TCP 服务，因此 IPv6 客户端可直接连接；
 * - 密码可选：password 为空时视为「无密码」，界面须向用户明示风险；
 * - 仅提供四项能力：status / preset / export / video；
 * - 协议为一行 JSON 请求 + 一行 JSON 响应，便于脚本调用（含 curl）。
 */
export interface RemoteRequest {
  cmd: string;          // status | preset | export | video
  password?: string;
  args?: string;
}

export interface RemoteReply {
  ok: boolean;
  data?: string;
  error?: string;
}

export class RemoteServer {
  private srv4: net.TCPSocketServer | null = null;
  private srv6: net.TCPSocketServer | null = null;
  private clients: net.TCPSocketConnection[] = [];
  private listening: boolean = false;
  private port: number = 0;
  private password: string = '';
  private handler: (req: RemoteRequest) => RemoteReply = (req: RemoteRequest): RemoteReply => {
    const r: RemoteReply = { ok: false, error: 'no handler' };
    return r;
  };

  public isListening(): boolean {
    return this.listening;
  }

  public getPort(): number {
    return this.port;
  }

  public setPassword(pw: string): void {
    this.password = pw;
  }

  public hasPassword(): boolean {
    return this.password.length > 0;
  }

  public start(port: number, handler: (req: RemoteRequest) => RemoteReply): void {
    this.port = port;
    this.handler = handler;
    this.startStack(true, port);
    this.startStack(false, port);
    this.listening = true;
    hilog.info(0x0000, 'OpenSPHRemote', `listening on port ${port} (IPv4+IPv6)`);
  }

  private startStack(ipv4: boolean, port: number): void {
    try {
      const srv: net.TCPSocketServer = net.constructTCPSocketServerInstance();
      srv.on('connect', (conn: net.TCPSocketConnection) => {
        hilog.info(0x0000, 'OpenSPHRemote', `client connected (${ipv4 ? 'v4' : 'v6'})`);
        this.clients.push(conn);
        conn.on('message', (info: net.SocketMessageInfo) => {
          this.onData(conn, info);
        });
        conn.on('close', () => {
          hilog.info(0x0000, 'OpenSPHRemote', 'client closed');
        });
      });
      const addr: net.NetAddress = {
        address: ipv4 ? '0.0.0.0' : '::',
        port: port,
        family: ipv4 ? 1 : 2
      };
      srv.listen(addr).then(() => {
        hilog.info(0x0000, 'OpenSPHRemote', `${ipv4 ? 'IPv4' : 'IPv6'} listening ${addr.address}:${port}`);
      }).catch((e: Object) => {
        hilog.warn(0x0000, 'OpenSPHRemote', `listen failed (${ipv4 ? 'v4' : 'v6'}): ${JSON.stringify(e)}`);
      });
      if (ipv4) {
        this.srv4 = srv;
      } else {
        this.srv6 = srv;
      }
    } catch (e) {
      hilog.warn(0x0000, 'OpenSPHRemote', `construct failed: ${String(e)}`);
    }
  }

  private onData(sock: net.TCPSocketConnection, info: net.SocketMessageInfo): void {
    let text: string = '';
    try {
      const arr: Uint8Array = new Uint8Array(info.message);
      for (let i = 0; i < arr.length; i++) {
        text += String.fromCharCode(arr[i]);
      }
    } catch (e) {
      return;
    }
    let req: RemoteRequest | null = null;
    try {
      req = JSON.parse(text.trim()) as RemoteRequest;
    } catch (e) {
      this.reply(sock, { ok: false, error: 'bad json' });
      return;
    }
    if (req === null) {
      this.reply(sock, { ok: false, error: 'bad json' });
      return;
    }
    // 密码校验（若设置了密码）
    if (this.password.length > 0) {
      const given: string = req.password === undefined ? '' : req.password;
      if (given !== this.password) {
        this.reply(sock, { ok: false, error: 'unauthorized' });
        return;
      }
    }
    const resp: RemoteReply = this.handler(req);
    this.reply(sock, resp);
  }

  private reply(sock: net.TCPSocketConnection, resp: RemoteReply): void {
    interface ReplyJson {
      ok: boolean;
      data?: string;
      error?: string;
    }
    const obj: ReplyJson = { ok: resp.ok };
    if (resp.data !== undefined) {
      obj.data = resp.data;
    }
    if (resp.error !== undefined) {
      obj.error = resp.error;
    }
    const payload: string = JSON.stringify(obj) + '\n';
    const buf: ArrayBuffer = new ArrayBuffer(payload.length);
    const view: Uint8Array = new Uint8Array(buf);
    for (let i = 0; i < payload.length; i++) {
      view[i] = payload.charCodeAt(i) & 0xff;
    }
    sock.send({ data: buf }).catch((e: Object) => {
      hilog.warn(0x0000, 'OpenSPHRemote', `send failed: ${JSON.stringify(e)}`);
    });
  }

  public stop(): void {
    this.listening = false;
    try {
      if (this.srv4 !== null) {
        this.srv4.close();
        this.srv4 = null;
      }
    } catch (e) {
      // ignore
    }
    try {
      if (this.srv6 !== null) {
        this.srv6.close();
        this.srv6 = null;
      }
    } catch (e) {
      // ignore
    }
    for (const c of this.clients) {
      try {
        c.close();
      } catch (e) {
        // ignore
      }
    }
    this.clients = [];
    hilog.info(0x0000, 'OpenSPHRemote', 'stopped');
  }
}
