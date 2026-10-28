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
