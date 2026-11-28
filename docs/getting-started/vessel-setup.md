---
title: Vessel & Staging Setup
parent: Getting Started
nav_order: 2
---

# Vessel & Staging Setup

You do **not** have to use the bundled `Falcon9forRecovery.craft` — custom payloads, satellites, or Dragon capsules all work as long as your rocket meets the setup rules below.

---

## 1. Engine & Hardware Setup

| Part | Required Setup |
| :--- | :--- |
| **Stage 1 Cluster (`TE_19_F9_S1_Engine`)** | Set RealFuels config to **`Merlin1D++`** on all 3 modes (`AllEngines` / `ThreeLanding` / `CenterOnly`) |
| **Stage 2 Engine (`TE_19_F9_S2_Engine`)** | Set RealFuels config to **`Merlin1DVac+`** |
| **Grid Fins** | 4x KRE Medium Titanium Grid Fins (`Grid Fin M Titanium`) mounted radially on the interstage — verify FAR control axes are set to **Pitch = `-100`**, **Yaw = `-100`**, **Roll = `0`** on all 4 fins |
| **Landing Legs** | 4x KRE Falcon Landing Gear Mk2 Medium (`KRE-FalconLegMk2-M`) |
| **Stage 1 & 2 RCS** | 2x `TE2_19_F9_CGT` (Nitrogen) on Stage 1; `TE_F9_S2_RCS` (Nitrogen) on Stage 2 |

> The bundled patches in `GameData/kOS-Falcon-GNC/Patches/` configure these parts automatically to match `vessels/tundra_f9_profile.ks`.

---

## 2. Standard 6-Stage Sequence

Arrange your staging list in the following order:

| Stage | Triggered By | Contents & Notes |
| :---: | :--- | :--- |
| **Stage 5** | Auto (`ascent.ks`) | Stage 1 `Merlin1D++` cluster ignition + Stage 1 Cold Gas Thrusters |
| **Stage 4** | **Manual (`SPACE`)** | Launch Clamp / Transporter Erector release — **press `SPACE` as soon as possible after ignition** so liftoff timing matches `estimate.ks` |
| **Stage 3** | **Manual (`SPACE`)** | Interstage decoupler **ONLY** — keep this separate from MVac ignition so Stage 2 can perform 2.0 s of RCS ullage and safely clear the interstage |
| **Stage 2** | Auto (`ascent.ks`) | Stage 2 `Merlin1DVac+` ignition + Stage 2 RCS |
| **Stage 1** | **Manual (`SPACE`)** | Payload fairing jettison (press `SPACE` after the `91 km` altitude reminder) |
| **Stage 0** | Manual (`SPACE`) | Payload adapter / spacecraft separation |

> **Note (`Falcon9forRecovery.craft`)**: The bundled v1.2.0 craft file will be updated to this 6-stage fairing layout in the next release; if you load the v1.2.0 craft today, move the fairings into Stage 1 in the VAB.

---

## 3. kOS Processor Placement

Place **two** kOS CPUs on the rocket:
1. **Stage 2 CPU** (on the Payload Adapter or upper stage): runs `estimate.ks` on the pad and `ascent.ks` through SECO.
2. **Stage 1 CPU** (on the Interstage): runs `recovery.ks` after switching back to Stage 1 via **FMRS**.
