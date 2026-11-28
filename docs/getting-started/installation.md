---
title: Installation & Dependencies
parent: Getting Started
nav_order: 1
---

# Installation & Dependencies

## Required Mods

| Mod | Version / Link |
| :--- | :--- |
| **Kerbal Space Program** | `1.12.x` (tested on `1.12.5`) |
| **ModuleManager** | `>= 4.2.0` |
| **kOS (Kerbal Operating System)** | `>= 1.4.0` |
| **Real Solar System (RSS)** or **Sol** | [RSS Forum Thread](https://forum.kerbalspaceprogram.com/topic/177216-112-real-solar-system/) · [Sol Forum Thread](https://forum.kerbalspaceprogram.com/topic/229428-112x-sol-a-modern-recreation-of-our-home-system-at-real-quarter-and-stock-scale/) |
| **Realism Overhaul (RO)** | [GitHub](https://github.com/KSP-RO/RealismOverhaul) (plus all RO dependencies) |
| **Ferram Aerospace Research Continued (FAR)** | [Forum Thread](https://forum.kerbalspaceprogram.com/topic/179445-18-112-ferram-aerospace-research-continued-v01605-mader-030422/) |
| **Tundra Exploration** | [Forum Thread](https://forum.kerbalspaceprogram.com/topic/166915-112x-tundra-exploration-v72-april-6th-2026-restockalike-spacex-falcon-9-crew-dragon-xl-haven-1/) |
| **Kerbal Reusability Expansion (KRE)** | [Forum Thread](https://forum.kerbalspaceprogram.com/topic/195546-112x-kre-kerbal-reusability-expansion/) |
| **FMRS Continued** | [Forum Thread](https://forum.kerbalspaceprogram.com/topic/157214-112x-flight-manager-for-reusable-stages-fmrs-now-with-recoverycontroller-integration/) |

## Recommended & Optional Mods

- **[ASDS-Manager](https://github.com/tthirteenttt/ASDS-Manager)** — Automatically syncs `asds_predicted.ks`, deploys the ASDS drone ship downrange, and locks the barge deck.
- **Waterfall**, **RealChute**, **RealAntennas**, **NearFutureSolar** — Supported out of the box by the bundled ModuleManager patches.
- **Trajectories** — Helpful visual cross-check for unpowered impact prediction.
- **Physics Range Extender (PRE)** — Keeps the ASDS drone ship loaded at longer ranges.

---

## Option 1: Manual Installation (Current)

Download the latest `kOS-Falcon-GNC-v*.zip` from [GitHub Releases](https://github.com/tthirteenttt/kOS-Falcon-GNC/releases) and copy the files into your KSP directory:

1. Copy `GameData/kOS-Falcon-GNC/` into `<KSP_ROOT>/GameData/`.
2. Copy everything inside `Ships/Script/` into `<KSP_ROOT>/Ships/Script/` (kOS Archive `0:/`).
3. Copy `Ships/VAB/Falcon9forRecovery.craft` into `<KSP_ROOT>/saves/<YourSave>/Ships/VAB/`.

### Upgrading from v1.1.0 or Legacy Manual RO Packs

If you previously installed v1.1.0 or manual third-party Tundra/KRE RO files, remove those old folders before launching KSP so the standalone `GameData/kOS-Falcon-GNC/` patches load cleanly:
- Delete `GameData/RealismOverhaul/RO_SuggestedMods/TundraMods/` (if present)
- Delete `GameData/RealismOverhaul/RO_SuggestedMods/KerbalReusabilityExpansion/` (if present)
- Delete `GameData/RealismOverhaul/Waterfall_Configs/TundraMods/` (if present)
- Delete `GameData/RealismOverhaul/Waterfall_Configs/KerbalReusabilityExpansion/` (if present)
- Ensure stock `TundraExploration/Parts/Ghidorah9/TE_19_F9_S1_Engine.cfg` and `KerbalReusabilityExpansion/GridFinsTitanium/GridFin Titanium M.cfg` are unmodified.

---

## Option 2: Install via CKAN *(Pending Maintainer Approval — Not Yet Available)*

The NetKAN pull request for **`kOS-Falcon-GNC`** has been submitted to `KSP-CKAN/NetKAN` and is currently awaiting maintainer review. Once approved and indexed, CKAN will install:
- `GameData/kOS-Falcon-GNC/` (RO / FAR / Waterfall patches & MIT decals)
- `Ships/Script/` (kOS scripts)
- `Ships/VAB/Falcon9forRecovery.craft` (example Falcon 9 Block 5 craft)
