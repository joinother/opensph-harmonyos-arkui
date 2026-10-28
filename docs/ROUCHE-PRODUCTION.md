# 洛希极限撕裂视频 · 出片手册

## 一键出片流程（设备连上后）

```bash
source /tmp/opensph2.env && cd "$PA"
hdc install entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa force-start -a ArkAbility -b com.opensph.app
# 界面：点「渲染」→「渲染模拟视频（4K60）」
# 该菜单项会调用 C++ 原生预设 buildRochePreset() 建场景，并启动 4K/60fps/600 帧导出
```

导出写入设备路径：
```
/data/app/el2/100/base/com.opensph.app/haps/entry/files/videos/opensph-export.mp4
```

取回：
```bash
hdc file recv /data/app/el2/100/base/com.opensph.app/haps/entry/files/videos/opensph-export.mp4 \
  ~/Desktop/opensph-videos/moon-roche-4k60.mp4
```

## 场景参数（`buildRochePreset()`，C++ 原生，绕开字符串键）

| 项 | 值 | 说明 |
|---|---|---|
| 地球半径 | 1.2742e7 m | 放大 2 倍以降低数密度（提速 ~3.6×） |
| 月球半径 | 3.474e6 m | |
| 月球轨道 | 2.8e7 m（≈2.2 R⊕） | 洛希极限（2.44 R⊕）内侧 |
| 初速 | `KeplerianVelocityIc`（以地球为引力源） | v = √(GM/r) |
| 合并 | `JoinParticlesJob`：`com=false`、`unique_flags=true` | 不质心归零 |
| 引力 | `GRAVITY_SOLVER=BARNES_HUT` | |
| 碎裂 | `RHEOLOGY_DAMAGE=SCALAR_GRADY_KIPP` | |
| 屈服 | `RHEOLOGY_YIELDING=DRUCKER_PRAGER` | |
| 时间步 | `TIMESTEPPING_MAX_TIMESTEP=100 s` | |
| 模拟总时长 | 2500 s | 覆盖约 1/10 轨道周期 |
| 输出 | 3840×2160 / 60fps / 600 帧 / 40 Mbps | |

## 关键经验（踩过的坑）

1. **不要用 `setNodeSetting` 从 ArkTS 写数值型设置**：`float/int/vector` 全部 `matched=0`（键名两侧不一致），只有 `bool/enum` 生效；强行后缀匹配会命中错误条目触发内核断言 → 进程崩溃。
2. **正确做法**：在 C++ 里 `makeNode<...>()` + `getSettings().set(...)`，类型由编译期保证。
3. **帧数几乎不花钱，模拟时间才花钱**：帧间隔 = `duration / frames`，因此 600 帧与 24 帧的模拟成本相同。
4. **观测进度**：`hilog` 每 10 帧输出 `progress n/total simTime=...`；设备日志缓冲轮转很快，必须用后台 `hdc shell hilog > file` 持续抓取。
5. **渲染结束才写 moov 原子**：文件在跑完前 ffprobe 会报 `moov atom not found`，这是正常的，不是损坏。
6. 单帧耗时随演化后期骤增（CFL 步长变小），这是**撕裂正在发生**的侧面证据。

## 已知限制

- 4K 全流程预计 40–60 分钟（模拟主导）。
- 相机取景按整团包围球自适应，两体分离较大时画面留白偏多。
- 双纹理槽已实现（`setTexture(slot, ...)`）但 ArkTS 侧尚未上传两张贴图，当前两个天体共用类月球贴图。
