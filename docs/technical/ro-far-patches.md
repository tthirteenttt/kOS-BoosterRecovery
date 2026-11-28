---
title: RO / FAR / Waterfall Patch Suite
parent: Technical Reference
nav_order: 2
---

# Clean-Room RO / FAR / Waterfall Patch Suite

Because upstream **Realism Overhaul** does not ship Tundra Exploration or Kerbal Reusability Expansion (KRE) configs by default, **kOS-Falcon-GNC** bundles a standalone, **clean-room, MIT-licensed, non-destructive** ModuleManager patch suite under `GameData/kOS-Falcon-GNC/`.

## Conflict-Safe Two-Layer Architecture

- **Zero File Overwrites**: `GameData/` contains only `kOS-Falcon-GNC/`; no upstream RO, Tundra, or KRE files are touched, and **zero `:FINAL` passes** are used.
- **Layer 1 (`01`–`06`) — Base RO Conversion**: Guarded by `:HAS[~RSSROConfig[True]]` + internal marker tag (`kOSFalconGNC_BaseRO`, cleaned in `:LAST[kOS-Falcon-GNC]`) so it coexists peacefully with any third-party RO pack.
- **Layer 2 (`07`–`08`) — GNC Parity, FAR Grid Fin & Waterfall**: Guarantees exact calibration parity for `kOS-Falcon-GNC` (`:BEFORE[FerramAerospaceResearch]` grid fin conversion, 5° gimbal, 5 ignitions/TEATEB, separation force, S1/S2 RCS, UHF telemetry, and RO-scaled Waterfall plumes).

---

## Patch Files (99 Parts Covered)

| Patch File | Scope & Highlights |
| :--- | :--- |
| `01_RO_Tundra_Falcon9_FH.cfg` | Falcon 9 Block 4/5, Falcon Heavy, Octaweb/9x Merlin 1D, single M1D, standard & short-nozzle MVac, S1 CGT, S2 RCS, fairings, rideshare adapters, and MIT decal paths |
| `02_RO_Tundra_Falcon1_F9v10.cfg` | Falcon 1 (`1.68 m` -> `1.344x`, official RO `Merlin1` & `Kestrel` templates) and Falcon 9 v1.0 (`Bagorah 9`, 9x `Merlin1C` + `Merlin1CVac`) |
| `03_RO_Tundra_LaunchClamps.cfg` | LC-39A, SLC-40, and SLC-4E Transporter Erectors (`1.48x`, power & cryogenic boiloff replenishment) |
| `04_RO_Tundra_Dragon.cfg` | Dragon 1 (`GiganV2`), Dragon 2 Crew / Cargo / I4 (`RodanV2`), and Dragon XL (`GiganXL`): 8x SuperDraco, 16x 400 N Draco, PICA-3 `heatShieldTag = Lunar`, lifting reentry `AdjustableCoMShifter`, RealChute drogues + 4x 35 m mains, and 2.0 kW trunk solar array |
| `05_RO_Tundra_Technologies.cfg` | Optional (`:NEEDS[TundraTechnologies]`): Haven-1 (`Gaira`), Iridium NEXT, New Horizons, and Starlink dish (20 parts) |
| `06_RO_KRE.cfg` | All 30 KRE parts: Aluminum & Titanium Grid Fins, Falcon/Mk2/Aero/Hex/Shepard landing legs, BoosterWing, Cold Gas Thrusters, and KRE SuperDraco / `NASADock` capsule parts |
| `07_GNC_FAR_Overrides.cfg` | `:BEFORE[FerramAerospaceResearch]` FAR conversion for `Grid Fin M Titanium` + Layer 2 Falcon 9 GNC calibration guarantees |
| `08_RO_Waterfall.cfg` | Optional (`:NEEDS[Waterfall]`): rescales native TE/TT Waterfall templates (`1.48x` / `1.344x`), aligns MVac offset (`Z = 0.305`), adds `ROWaterfall` plumes for missing parts, and softens Stage 1 `TE2_19_F9_CGT` cold-gas nitrogen into a realistic translucent mist cone |

---

## Aerospace Data Cross-Verification Summary

Verified against the **SpaceX Falcon User's Guide (Mar 2025)**, Wikipedia technical tables, and official RO built-in templates (`Merlin1_Config.cfg`, `SuperDraco_Config.cfg`, `Kestrel_Config.cfg`):

| Vehicle / Subsystem | Reference Specification | Patch Configuration |
| :--- | :--- | :--- |
| **F9 / FH Core Diameter** | `3.66 m` (`3.7 m` nominal) | `rescaleFactor = 1.48` (`3.70 m`) |
| **Stage 1 Propellant (`TE_19_F9_S1_Tank`)** | `~411 t` subcooled RP-1/LOX | `5.66 t` dry, `Cryogenic` `397,159.68 L` (`basemass = -1`) |
| **Stage 1 Cluster (`TE_19_F9_S1_Engine`)** | 9x M1D++ `7,605–7,686 kN` SL / `8,227 kN` Vac (`288.5 / 311 s`) | `6.32 t` (9x `0.47 t` + `2.09 t` Octaweb), `All: 2970–8227.08 kN` / `Three: 990–2742.36 kN` / `Center: 330–914.12 kN`, `5` ignitions, `5°` gimbal |
| **Stage 1 Dry Stack (GNC Parity)** | `22.2–25.6 t` | `21.85 t` dry + CGT N2 ≈ **`22.2 t`** (matches `tundra_f9_profile.ks`) |
| **Stage 2 Tank & MVac** | `92.7–107.5 t` prop, `3.9–4.0 t` dry, MVac `934–981 kN` / `348 s` (short `338 s`) | `3.0 t` tank (`101,325 L`), official `Merlin1` template (`Merlin1DVac+` `934.12 kN / 348 s` + `Merlin1DVac+_Short_Nozzle` `338 s / 5 ignitions`), total S2 dry `3.97 t` |
| **Dragon 2 (`RodanV2`)** | `~7.7 t` dry w/ trunk, `2,562 kg` NTO/MMH, 8x `71 kN` SuperDraco, 16x `400 N` Draco, 2x drogues + 4x `35 m` mains, `2 kW` trunk solar | `7.66 t` total dry, `568 kN` SuperDraco (`280/240 s`), `0.4 kN` Draco (`300/110 s`), RealChute `7.8 m` / `70 m` equiv. dia (`~7 m/s` splashdown), `2.0 kW` trunk solar |
| **Falcon 1 & Falcon 9 v1.0** | F1 `1.68 m` dia (M1A/1C + Kestrel); F9 v1.0 `333 t` GLOM (9x M1C + M1CVac) | F1 `1.344x` (`20.9 kL` / `4.15 kL`, RO `Merlin1` + `Kestrel`); F9 v1.0 `1.48x` (`235 kL` / `48 kL`, 9x `Merlin1C` + `Merlin1CVac`) |
