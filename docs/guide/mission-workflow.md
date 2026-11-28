---
title: Mission Workflow (EN)
parent: Mission Guide
nav_order: 1
---

# Mission Workflow (English)

> 中文用户请查看：[使用教程（中文）](mission-workflow-zh.html)

This guide walks through a complete Falcon 9 Block 5 launch, Stage 2 orbital insertion, and **FMRS** Stage 1 booster recovery.

---

## Pre-Launch Checklist

Before rolling out to the pad, double-check these 4 items:
1. **Engines**: Stage 1 cluster (`TE_19_F9_S1_Engine`) set to **`Merlin1D++`** on all modes; Stage 2 MVac (`TE_19_F9_S2_Engine`) set to **`Merlin1DVac+`**.
2. **Grid Fin Axes**: All 4 interstage grid fins have **Pitch = `-100`**, **Yaw = `-100`**, **Roll = `0`**.
3. **6-Stage Sequence**:
   - **Stage 5 (Auto)**: Stage 1 `Merlin1D++` + Stage 1 Cold Gas RCS
   - **Stage 4 (Manual `SPACE`)**: Launch clamps / strongback release
   - **Stage 3 (Manual `SPACE`)**: Interstage decoupler **only**
   - **Stage 2 (Auto)**: Stage 2 `Merlin1DVac+` + Stage 2 RCS
   - **Stage 1 (Manual `SPACE`)**: Payload fairings
   - **Stage 0 (Manual `SPACE`)**: Payload separation
4. **kOS & FMRS**: One kOS CPU on Stage 2, one on the Stage 1 interstage, and **FMRS** enabled.

---

## Step 1: Configure Mission Parameters

Edit the two config files in `<KSP_ROOT>/Ships/Script/config/`:

### 1.1 `ascent_config.ks`
- Set `TARGET_ORBIT`: `PERIAPSIS`, `APOAPSIS`, `INCLINATION`, and `LAN_MODE` (`"IGNORE"` to launch immediately, or `"FIXED"` to auto-warp to a target orbital plane).
- Set `RECOVERY_MODE` (`"ASDS"` or `"RTLS"`).
- Set `MECO_MASS` (total rocket mass in metric tons at MECO, **excluding launch clamps**). Conservative starting values:
  - **ASDS**: `170 t + payload mass`
  - **RTLS**: `210 t + payload mass`
- Set `TARGET_PITCH_END` (**`24°–28°`** for ASDS, **`32°–38°`** for RTLS).

### 1.2 `recovery_config.ks`
- Make sure `RECOVERY_MODE` matches `ascent_config.ks`.
- **ASDS mode**: Keep `LANDING_SITE` set to `PREDICTED_ASDS_LAT` / `PREDICTED_ASDS_LNG` (filled automatically by `asds_predicted.ks`). `ASDS_PROFILE["DECK_ELEVATION"]` defaults to `5.5 m` (for the ASOG barge); set it to `0.0` for water landings without a barge.
- **RTLS mode**: Enter your landing pad coordinates in `LANDING_SITE` as **decimal degrees with at least 6 decimal places**.

See the [Configuration Reference](configuration.html) for the full list of options.

---

## Step 2: Run Pre-Flight Trajectory Prediction (`estimate.ks`)

With the rocket sitting stationary on the launchpad, open any kOS terminal and run:

```kerboscript
SWITCH TO 0.
RUN estimate.
```

What `estimate.ks` does:
1. Simulates the full flight (ascent, entry burn, glide, and hoverslam).
2. Reports **Stage 1 recovery fuel margin**, **Max-Q**, and **Stage 2 delta-V margin**. Adjust `MECO_MASS` and `TARGET_PITCH_END` and re-run if needed.
3. Saves the optimal drone ship coordinates to `0:/config/asds_predicted.ks` (works automatically with [ASDS-Manager](https://github.com/tthirteenttt/ASDS-Manager)). **If flying RTLS mode, ignore the predicted ASDS coordinates.**

---

## Step 3: Launch & Stage 2 Orbital Insertion (`ascent.ks`)

Open the **Stage 2 kOS terminal** and run:

```kerboscript
SWITCH TO 0.
RUN ascent.
```

Watch for **3 manual `SPACE` prompts** during ascent:
1. **Release clamps ASAP after ignition (Stage 4)**: If `LAN_MODE = "FIXED"`, the script warps to the window automatically. As soon as Stage 1 ignites, **press `SPACE` right away to release the launch clamps** so the actual flight matches `estimate.ks`.
   > During ascent, the script automatically locks stowed grid-fin deflection to `0°` and disables Stage 1 RCS.
2. **Separate Stage 1 at MECO (Stage 3)**: Once Stage 1 cuts off at `MECO_MASS`, wait ~1 s for the thrust tail-off prompt, then **press `SPACE`** to decouple the interstage.
3. **Jettison fairings above `91 km` (Stage 1)**: After separation, `ascent.ks` runs 2.0 s of Stage 2 RCS ullage, automatically ignites MVac (Stage 2), and flies closed-loop UPEG to SECO. Press **`SPACE`** to deploy fairings when the terminal prints the `91 km` reminder.

---

## Step 4: Booster Recovery (`recovery.ks`)

After Stage 2 reaches orbit (SECO):
1. Open the **FMRS** window and jump back to the **Stage 1** separation save.
2. Open the **Stage 1 kOS terminal** and run:

```kerboscript
SWITCH TO 0.
RUN recovery.
```

From here, recovery is completely automatic:
- **Flip (`ST_FLIP`)**: Cold-gas RCS flips the booster tail-first in space.
- **Boostback (`ST_BOOSTBACK`, RTLS only)**: 3 Merlin engines burn back toward the landing pad.
- **Coast (`ST_COAST`)**: Deploys the 4 titanium grid fins and unlocks FAR grid-fin deflection to **`25°`**.
- **Entry Burn (`ST_ENTRY_BURN`)**: 3 Merlin engines fire to slow down for reentry, cutting off once speed/altitude/fuel gates are met.
- **Aero Glide (`ST_AERO_GLIDE`)**: Grid fins steer the booster toward the target using live impact prediction (RCS automatically turns off once aerodynamic authority is strong enough).
- **Hoverslam (`ST_LANDING_BURN` → `ST_TOUCHDOWN`)**: Center Merlin 1D ignites to brake, nulls horizontal error, deploys landing legs (`180 m`), locks strictly vertical below `12 m`, and cuts off at touchdown.

Once landed, use the **FMRS** window to return to the main mission and merge your save.
