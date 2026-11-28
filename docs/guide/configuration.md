---
title: Configuration Reference
parent: Mission Guide
nav_order: 3
---

# Configuration Reference

All user-tunable mission parameters live in two clean kOS lexicon files under `Ships/Script/config/`.

---

## 1. `ascent_config.ks`

### Top-Level & Staging

| Key | Default | Description |
| :--- | :--- | :--- |
| `MECO_MASS` | `180.0` | Target total stack mass (t) at MECO, excluding launch clamps. Baseline: `170 + payload` (ASDS), `210 + payload` (RTLS). |
| `MIN_MECO_ALT` | `40000.0` | Minimum ASL altitude (m) before MECO is permitted. |
| `RECOVERY_MODE` | `"ASDS"` | `"ASDS"` or `"RTLS"` — keep aligned with `recovery_config.ks`. |
| `FALLBACK_RESERVE_ON` | `TRUE` | Forces MECO early if Stage 1 hits the recovery propellant reserve floor. |
| `MAX_ASCENT_TIME` | `750.0` | Overall script safety runtime cap (s). |

### `TARGET_ORBIT`

| Key | Default | Description |
| :--- | :--- | :--- |
| `PERIAPSIS` | `200000.0` | Target periapsis altitude (m). Direct single-burn UPEG is accurate for `<= 300 km`. |
| `APOAPSIS` | `200000.0` | Target apoapsis altitude (m, `>= PERIAPSIS`). Supports MEO and `35786 km` GTO. |
| `INCLINATION` | `28.6` | Target inclination (deg, `>= |launch_lat|`; `> 90` for retrograde SSO). |
| `LAN_MODE` | `"IGNORE"` | `"IGNORE"` launches immediately; `"FIXED"` waits for the orbital plane window and locks LAN. |
| `LAN` | `0.0` | Target longitude of ascending node (deg, `0..360`, used in `"FIXED"` mode). |
| `LAN_LEAD_TIME` | `150.0` | Earth-rotation launch lead compensation (s) for `"FIXED"` LAN windows. |
| `AUTO_WARP` | `TRUE` | Automatically rails-warps to the launch window (BetterTimeWarp compatible) and stops before ignition. |

### `ASCENT_PROFILE`

| Key | Default | Description |
| :--- | :--- | :--- |
| `PITCH_START_ALT` | `250.0` | Radar altitude (m) to start pitchover (requires `Vz > 45 m/s`). |
| `PITCH_END_ALT` | `52000.0` | ASL altitude (m) where pitch reaches `TARGET_PITCH_END`. |
| `TARGET_PITCH_END` | `24.0` | Terminal Stage 1 pitch angle (deg; `24–28` ASDS, `32–38` RTLS). |
| `PITCH_CURVE_EXP` | `0.50` | Power-law shaping exponent (`< 1` pitches over earlier). |
| `MAX_AOA_DEG` | `5.0` | Reference AoA limit (deg), tightened dynamically above `2.5 kPa` dynamic pressure. |
| `AUTO_IGNITE` | `TRUE` | Automatically throttles up and fires Stage 5 liftoff ignition. |
| `USE_TARGET_AZIMUTH` | `TRUE` | Solves 3D inertial launch azimuth from `TARGET_ORBIT` (`FALSE` uses `MANUAL_AZIMUTH`). |
| `LAUNCH_SOUTH` | `"AUTO"` | `"AUTO"` / `"NEAREST"` (FIXED LAN) / `TRUE` (descending) / `FALSE` (ascending). |

### `STAGING` & `UPEG`

| Key | Default | Description |
| :--- | :--- | :--- |
| `STAGE_MASS_DROP` | `20.0` | Mass drop (t) confirming physical interstage separation. |
| `S2_CLEARANCE_WAIT` | `2.0` | Stage 2 RCS ullage and nozzle-clearance duration (s) before MVac ignition. |
| `S2_IGNITION_STAGE` | `TRUE` | Automatically triggers `STAGE` for MVac ignition after clearance. |
| `FAIRING_REMINDER_ALT` | `91000.0` | Altitude (m) to display manual fairing jettison reminder. |
| `UPEG.MAX_BURN_TIME` | `600.0` | Safety burn-time cap (s) for Stage 2 UPEG. |

---

## 2. `recovery_config.ks`

### Core Target & Mode Selection

| Key | Default | Description |
| :--- | :--- | :--- |
| `RECOVERY_MODE` | `"ASDS"` | `"ASDS"` or `"RTLS"` — must match `ascent_config.ks`. |
| `LANDING_SITE.LATITUDE` | `PREDICTED_ASDS_LAT` | Target latitude in decimal degrees (auto-populated by `estimate.ks` in ASDS mode; enter at least 6 decimal places for RTLS). |
| `LANDING_SITE.LONGITUDE` | `PREDICTED_ASDS_LNG` | Target longitude in decimal degrees (auto-populated by `estimate.ks` in ASDS mode; enter at least 6 decimal places for RTLS). |
| `INITIAL_STATE` | `"AUTO"` | Selects FSM entry state automatically from live altitude and vertical speed. |

### `GUIDANCE`, `AERO` & `LANDING_ATTITUDE`

| Key | Default | Description |
| :--- | :--- | :--- |
| `GUIDANCE.LEGS_DEPLOY_ALT` | `180.0` | Radar altitude (m) to extend landing legs. |
| `GUIDANCE.HOVERSLAM_MARGIN` | `30.0` | Safety altitude margin (m) on terminal hoverslam ignition trigger. |
| `AERO.MAX_AOA_DEG` | `16.0` | Nominal maximum grid-fin glide AoA command (deg). |
| `AERO.RCS_Q_CUTOFF` | `0.09` | Dynamic pressure (atm) above which glide RCS disables (re-enables with hysteresis below `0.06 atm` and during low-speed hoverslam). |
| `LANDING_ATTITUDE.MAX_TILT_DEG` | `32.0` | High-altitude landing zenith tilt cap (tapers smoothly to `0°`). |
| `LANDING_ATTITUDE.ALIGN_GATE_ALT` | `28.0` | Radar altitude (m) to finish horizontal centering and velocity nulling. |
| `LANDING_ATTITUDE.UPRIGHT_LOCK_ALT` | `12.0` | Radar altitude (m) below which attitude locks strictly vertical. |

### Mode Profiles (`ASDS_PROFILE` / `RTLS_PROFILE`)

| Parameter | ASDS Default | RTLS Default | Notes |
| :--- | :---: | :---: | :--- |
| `DECK_ELEVATION` | `5.5 m` | `0.0 m` | Set ASDS to `0.0` when testing water landings without a barge. |
| `COAST_ENTRY_ALT` | `68,000 m` | `58,000 m` | Entry burn interface altitude. |
| `COAST_PITCH_DEG` | `25.0°` | `62.0°` | Pre-entry glide/coast pitch alignment. |
| `EB_END_SPEED` | `800 m/s` | `700 m/s` | Target post-entry-burn velocity cutoff. |
| `EB_MIN_LANDING_PROP_T` | `4.6 t` | `4.6 t` | Hard propellant reserve floor protected for terminal hoverslam. |
| `GLIDE_MAX_AOA` | `16.0°` | `16.5°` | Mode-specific aerodynamic glide AoA ceiling. |
