---
title: 使用教程（中文）
parent: Mission Guide
nav_order: 2
---

# 使用教程（中文）

> English version: [Mission Workflow (EN)](mission-workflow.html)

本教程完整介绍基于 **FMRS** 的 Falcon 9 Block 5 发射、二级闭环入轨（UPEG）与一级自主回收（ASDS 海上驳船 / RTLS 陆地返场）操作流程。

---

## 发射前准备检查

在进入发射台之前，请确认以下 4 项：
1. **发动机配置**：一级九台发动机（`TE_19_F9_S1_Engine`）全部模式设为 **`Merlin1D++`**，二级真空梅林（`TE_19_F9_S2_Engine`）设为 **`Merlin1DVac+`**。
2. **栅格舵控制轴**：核对一级级间段四个栅格舵的俯仰（Pitch）和偏航（Yaw）控制均为 **`-100`**，滚转（Roll）控制为 **`0`**。
3. **6 级标准分级顺序**：
   - **Stage 5（起飞点火，由 `ascent.ks` 自动触发）**：一级 9 台发动机 + 一级冷气 RCS
   - **Stage 4（手动按 `SPACE`）**：发射塔架 / 发射夹具释放
   - **Stage 3（MECO 后手动按 `SPACE`）**：**仅放级间段分离器**（不要与二级 MVac 点火合并）
   - **Stage 2（脱离后由 `ascent.ks` 自动触发）**：二级 `Merlin1DVac+` 点火 + 二级 RCS
   - **Stage 1（手动按 `SPACE`）**：整流罩抛离（过 `91 km` 提示后手动触发）
   - **Stage 0（手动按 `SPACE`）**：载荷适配器分离
   > 注：v1.2.0 自带的 `Falcon9forRecovery.craft` 将在下个版本同步更新为上述 6 级布局；当前使用自带船体时，请在 VAB 中将整流罩单独放入 Stage 1。
4. **kOS 处理器与 FMRS**：二级与一级级间段各有一个 kOS 终端，并确保 **FMRS** 处于激活状态。

---

## 第一步：配置任务参数

打开 `<KSP根目录>/Ships/Script/config/` 下的两个配置文件：

### 1. 编辑 `ascent_config.ks`
- 设置目标轨道 `TARGET_ORBIT`：近地点 `PERIAPSIS`、远地点 `APOAPSIS`、倾角 `INCLINATION`，以及升交点赤经模式 `LAN_MODE`（`"IGNORE"` 立即发射；`"FIXED"` 自动加速等待轨道面窗口）。
- 设置回收模式 `RECOVERY_MODE`（`"ASDS"` 或 `"RTLS"`）。
- 设置一级关机目标总质量 `MECO_MASS`（单位：吨，**不含发射架质量**）。保守初始参考值：
  - **ASDS 模式**：`170 t + 载荷质量`
  - **RTLS 模式**：`210 t + 载荷质量`
- 调整重力转弯末段俯仰角 `TARGET_PITCH_END`（ASDS 建议约 **`24°–28°`**，RTLS 建议约 **`32°–38°`**）。

### 2. 编辑 `recovery_config.ks`
- 确认 `RECOVERY_MODE` 与 `ascent_config.ks` 中的回收模式一致。
- **ASDS 模式**：保持 `LANDING_SITE` 为 `PREDICTED_ASDS_LAT` / `PREDICTED_ASDS_LNG`（由 `asds_predicted.ks` 自动写入）。`ASDS_PROFILE["DECK_ELEVATION"]` 默认为 `5.5 m`（适配 ASOG 驳船甲板高度）；若无驳船直接海面测试请改为 `0.0`。
- **RTLS 模式**：将 `LANDING_SITE` 改为目标陆地着陆场的**十进制经纬度，至少精确到小数点后六位**。

详细参数含义请查阅 [Configuration Reference](configuration.html)。

---

## 第二步：发射前数值预测（`estimate.ks`）

火箭上台静止后，打开任意一个 kOS 终端运行：

```kerboscript
SWITCH TO 0.
RUN estimate.
```

脚本会自动完成以下工作：
1. 执行全流程数值积分（上升段 + 再入点火 + 气动滑翔 + Hoverslam）。
2. 输出 **一级回收燃料余量**、**Max-Q 动压** 与 **二级入轨 Δv 余量**。如余量偏紧或过剩，可微调 `MECO_MASS` 和 `TARGET_PITCH_END` 后重新运行。
3. 自动将最优无人船落点坐标写入 `0:/config/asds_predicted.ks`（推荐配合 [ASDS-Manager](https://github.com/tthirteenttt/ASDS-Manager) 自动同步部署无人船）。**若为 RTLS 模式，请忽略最优无人船落点坐标。**

---

## 第三步：发射与二级闭环入轨（`ascent.ks`）

打开 **二级 kOS 终端**，运行：

```kerboscript
SWITCH TO 0.
RUN ascent.
```

飞行过程注意以下 3 个手动节点：
1. **点火后尽快手动脱架（Stage 4）**：若开启 `LAN_MODE = "FIXED"`，脚本会自动时间加速至窗口。一级自动点火后，**请尽快手动按 `SPACE` 释放发射塔架**，避免实际飞行剖面与 `estimate.ks` 预测产生偏差。
   > 上升段脚本会自动将收起状态下的 FAR 栅格舵偏转锁为 `0°`，并关闭一级 RCS。
2. **MECO 后手动级间分离（Stage 3）**：一级达到 `MECO_MASS` 自动关机后，等待约 1 秒推力衰减提示，**手动按 `SPACE`** 触发级间分离。
3. **过 91 km 后手动抛整流罩（Stage 1）**：分离后脚本会自动执行 2.0 秒二级 RCS 沉底脱离、自动触发 MVac 点火（Stage 2）并切入 **UPEG 闭环制导**直至 SECO；通过 `91 km` 时终端会提示手动按 `SPACE` 抛弃整流罩。

---

## 第四步：一级自主回收（`recovery.ks`）

二级完成入轨（SECO）后：
1. 在 **FMRS** 面板中点击切回到一级分离存档点。
2. 打开 **一级 kOS 终端**，运行：

```kerboscript
SWITCH TO 0.
RUN recovery.
```

随后全程自动执行：
- **姿态翻转（`ST_FLIP`）**：大气外氮气冷气 RCS 翻转至逆行/返场姿态。
- **返场点火（`ST_BOOSTBACK`，仅 RTLS）**：3 台梅林引擎点火，修正落点至着陆场。
- **高空滑行（`ST_COAST`）**：自动展开 4 片钛合金栅格舵，同时自动解锁 FAR 舵面偏转程度至 **`25°`**。
- **再入点火（`ST_ENTRY_BURN`）**：3 台梅林引擎点火进一步减速，满足速度/高度/燃料保护阈值后自动关机。
- **气动滑翔（`ST_AERO_GLIDE`）**：基于实时落点预测的栅格舵闭环制导。
- **着陆自杀式点火（`ST_LANDING_BURN` → `ST_TOUCHDOWN`）**：中心梅林引擎点火减速、消除水平偏差、放出着陆腿、`< 12 m` 保持竖直着陆并关机。

着陆确认后，在 **FMRS** 窗口切回主任务合并存档即可完成整次任务。

---

## 常见问题速查

- **物理加速倍率**：建议全程不超过 **`1x–2x`** 物理加速；过高的物理加速倍率（`3x–4x`）会导致一级落点精度和二级入轨精度下降（`ascent.ks` 在检测到二级姿态异常时也会自动降回 `1x`）。
- **载人龙 / 货运龙飞船**：龙飞船作为载荷时，由于气动外形与常规整流罩构型差异较大，`estimate.ks` 对 ASDS 的落点预测不可靠，建议按真实任务习惯直接采用 **RTLS 模式**。
- **高圆轨任务**：单次燃烧 UPEG 在近地点 `<= 300 km` 时精度较好；若目标为更高的圆轨，请先设为 `200 km x 目标远地点` 转移轨道，再在远地点自行圆化。
