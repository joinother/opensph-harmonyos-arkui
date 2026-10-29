# OpenSPH · 鸿蒙 ArkUI 版

把 [OpenSPH](https://github.com/sevecek/OpenSPH)（SPH / N-body 天体物理模拟器）移植到鸿蒙电脑端（HarmonyOS PC / 2in1），
界面层用 **ArkTS / ArkUI 完全重写**，物理内核沿用 OpenSPH 上游 C++ 代码，通过 N-API 桥接。

> 本仓库只包含**界面与桥接层源码**。上游 OpenSPH 内核、wxWidgets/Qt 移植层与预编译 `.so` 不在此仓库中，
> 需要按下方「构建」自行准备。

## 特性

### 界面
- 全中文界面（菜单、节点库、属性面板、通知、状态栏）；参数名按天体物理术语翻译
- 节点图编辑器：添加 / 拖拽 / 连线 / 删除 / 克隆 / 下游子树删除，画布平移与缩放
- 属性面板：113 项参数实时读写内核，支持布尔、枚举、整数、浮点、向量、区间
- 左右面板可拖拽调宽（含限幅与持久化）、可折叠；「视图」菜单提供加宽/复位
- 统一的动效规范（120/180/220ms，`EaseOut`/`Friction`），并提供「减少动效」开关一键归零
- 状态栏通知中心 + 系统通知

### 预览与渲染
- **C++ 侧光栅化渲染**（`splatPoints`）：深度排序 + 圆盘 splat + 高斯权重加法混合 + 半径色图 + Lambert/高光
  - 实测 1000×1000 预览：C++ 2–5ms + PixelMap 更新 0–7ms（约 60fps）
- 预览可**弹出为独立子窗口**（`createSubWindow`），支持拖动旋转
- 预览、子窗口、视频导出**共用同一份渲染代码**

### 视频导出
- 离线渲染（B）：方向（横屏/竖屏/方形）× 分辨率（720p–4K）× 帧率（24/30/60）× 帧数 × 码率
- 画质档位：快速 / 标准 / 高（2× 超采样后降采样）
- 一键预设：快速预览片 / 标准成片 / 高质量 4K
- 录制预览（A）：抓取预览画面实时编码
- 进度显示帧率与预计剩余时间；输出帧数与请求**严格一致**
- H.264 + MP4 直出（OH `OH_VideoEncoder` + `OH_AVMuxer`）

## 目录结构

```
entry/src/main/ets/pages/ArkMain.ets      # 全部界面（约 3900 行）
entry/src/main/ets/common/I18nZh.ets      # 中文本地化映射表
entry/src/main/ets/common/NotificationCenter.ets
entry/src/main/ets/pages/PreviewWindow.ets # 预览子窗口
entry/src/main/cpp/ark_bridge.cpp         # N-API 桥接 + C++ 光栅化渲染
entry/src/main/cpp/opensoh_bridge.cpp     # wx 版（回退路径）桥接
entry/src/main/cpp/CMakeLists.txt
```

## 构建

前置依赖（不在此仓库）：
1. OpenSPH 上游源码，并已产出 `build-ohos/core/libcore.a`
2. wxWidgets 的 OHOS 构建（仅回退路径需要）
3. DevEco Studio + HarmonyOS SDK（本项目在 API 26 / 2in1 上验证）

调整 `entry/src/main/cpp/CMakeLists.txt` 里的 `OPENSPH_SRC` / `WX_SRC` 指向你的本地路径，然后：

```bash
hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a ArkAbility -b com.opensph.app
```

`ArkAbility`（ArkUI）是默认入口；`QAbility` 是保留的 wx/Qt 界面，可回退：

```bash
hdc shell aa start -a QAbility -b com.opensph.app
```

## 验证状态

在 HUAWEI HAD-W32（2in1, API 26）实机验证：
- 节点库 6 类共 59 种作业，逐个创建 + 加载属性面板 **152 次点击无崩溃**
- 导出帧数精确（请求 90 → 90 帧；120 → 120 帧）
- 预览/子窗口/导出渲染一致
- wx 回退路径（QAbility）可正常启动

## 测试报告

全功能遍历测试（菜单、右键菜单、导出选项、属性面板 6 类控件、会话往返、模拟、画布、渲染）的完整结果见 [docs/TEST-REPORT.md](docs/TEST-REPORT.md)：350 次交互、零闪退、8 个已修缺陷（含 3 个高危）。

## 许可

界面与桥接代码：随上游保持一致。OpenSPH 内核版权归其原作者（Pavel Ševeček）。

## 纹理渲染与过程视频（新增）

### 球面纹理
- C++ 侧 `splatPoints` 采用两阶段：粒子只负责铺**深度图**，颜色按**逐像素**重建法线后采样贴图（否则每颗粒子会变成一块同色圆盘，放大后是"波点球"）。
- UV 由法线反旋转回**物体空间**再计算（`u = 0.5 + atan2(z,x)/2π`、`v = 0.5 − asin(y/r)/π`），所以贴图随天体自转，而不是跟着相机滑动。
- 支持**双纹理槽**（`setTexture(slot, w, h, rgba)`）：主天体/次天体各用一张贴图，采样点按"最远点对"聚类分成两组，各自算球心与半径。
- 内置程序化贴图：类地球（海洋/大陆/极冠/云）、类月球（月海 + 90 个环形山，中心暗边缘亮），1024×512 等距圆柱，无版权问题、体积为零。

### 模拟驱动的离线渲染
- `startSimExport(handle, options)`：在模拟的 `onTimeStep` 里按时间轴切帧（`dt = duration / frames`），每帧取当前粒子位置渲染，因此每帧都来自真实演化，而不是旋转静态几何。
- 分辨率/帧率/帧数/码率/时长可配；实测 3840×2160、60fps、600 帧可用。
- 进度可用 `simExportStatus()` 轮询（`rendered / total`）。

### 洛希极限场景（构建器）
`buildRocheScenario()` 用已注册作业类名程序化搭图（不经 gui 层，避免 Presets 的 wx 依赖）：

```
地球 IC ─→ join(particles A) ─→ SPH run（Barnes-Hut 自引力 + Grady-Kipp 碎裂）
月球 IC ─→ transform(offset) ─→ set Keplerian velocity ─→ join(particles B)
```

关键点：
- 轨道速度必须用 `set Keplerian velocity`（以地球为引力源）计算 `v = √(GM/r)`；用 `join` 的 `velocity` 参数是**整系统偏移速度**，不会产生绕转。
- `join` 必须显式 `com=false`，否则质心归零会让两天体互相靠拢。
- 物理时间尺度是小时级（地球密度对应动力时间 ~20 分钟），因此验证时可用「整体放大天体」降低数密度来提速（实测约 3.6 倍）。

### 已知限制
- 通过桥接 `setNodeSetting(handle, 'particles.count', ...)` 修改粒子数**不生效**（readback 恒为默认 10000）；只有 UI 输入框修改才生效。
- 1 秒墙钟约推进 1.2 秒模拟（2.1 万粒子 + Barnes-Hut + 损伤模型 + CFL 小步长），这是当前唯一的速度瓶颈。

## 贴图与远程接口（新增）

### 按天体贴图（不是全局设置）
- 贴图属于**天体节点**，入口在节点卡片的 **⋯ → 设置贴图…**（早期版本误放在「视图」菜单，已纠正）。
- C++ 侧维护天体表 `[{cx,cy,cz,r,slot}]`（`ark.setBodyTextures(json)`），渲染时每颗粒子按「离哪个天体最近（用半径归一化）」决定用哪张贴图，最多 8 个天体 / 8 张贴图槽。
- 逐像素着色：每像素记录所属天体与贴图槽，用该天体自己的球心/半径重建法线，再用对应槽位采样——这样月球贴图不会被地球的球心拉歪。
- **单天体判定**：两簇中心距离 < 1.05×(r0+r1) 时视为一个天体，否则单个球会被切成两半、右半法线错位导致颜色发白。

### 手动选图
- 卡片 ⋯ → 设置贴图… → 系统文件选择器（png/jpg/webp）→ `image.createImageSource` 解码 → RGBA → `ark.setTexture(slot, w, h, buf)`。
- 图片要求**等距圆柱（2:1 经纬展开）**；普通照片可用但会变形。
- 贴图生成放在主线程曾导致 ANR（1024×512×2 张 + 90 个环形山 ≈ 4700 万次判定），现降为 512×256 / 40 个环形山。

### 远程接口（默认关闭）
- 入口：视图 →「开启远程接口」；面板可设端口（默认 8099）、密码（可留空，界面明示风险）、允许广域网（**强制要求密码**）。
- 双栈监听：IPv4 `0.0.0.0` + IPv6 `::`，日志会打印两条 listening。
- 协议：一行 JSON 请求 → 一行 JSON 响应。
  ```bash
  echo '{"cmd":"status"}' | nc 192.168.1.56 8099
  # {"ok":true,"data":"{\"remote\":true,\"port\":8099,...}"}
  ```
- 能力：`status` / `preset`（建场景并同步画布）/ `export` / `video`。
- 实测：Mac 通过 TCP 直连设备 8099，`status` 与 `video` 均返回正确 JSON。
- 限制：广域网需设备有公网 IPv6 且上级网络放行入站；当前设备未分配任何 IPv6 地址，故 IPv6 广域链路无法在实机验证。

### 画布自动同步
- 新增 `ark.listJobGraph()`：枚举内核全部作业节点与已连接槽位（provider→consumer）。
- ArkTS `syncCanvasFromKernel()` 与画布 diff，缺节点补节点、缺连线补连线——所以预设/脚本/远程接口建的图都会自动出现在画布上。
