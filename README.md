# kOS-Falcon-GNC

Autonomous Falcon 9 Block 5 (`Ghidorah 9`) launch, closed-loop upper-stage orbital insertion (UPEG), and first-stage booster recovery (ASDS / RTLS) autopilot suite for **Kerbal Space Program 1 (1.12.x)** under **RSS / RO / FAR**.

---

## 1. Dependencies

### Required Mods
- **Kerbal Space Program**: 1.12.x (tested on 1.12.5)
- **ModuleManager**: >= 4.2.0
- **kOS (Kerbal Operating System)**: >= 1.4.0
- **Real Solar System (RSS)** / **Sol**
- **Realism Overhaul (RO)** (including RealFuels)
- **Ferram Aerospace Research Continued (FAR)**
- **Tundra Exploration** (Falcon 9 / Heavy, Falcon 1, Dragon 1/2/XL, Launch Clamps)
- **Kerbal Reusability Expansion (KRE)** (Titanium Grid Fins & Landing Legs)
- **FMRS (Flight Manager for Reusable Stages)** — required to switch back to Stage 1 after Stage 2 reaches orbit

### Bundled Standalone RO/FAR ModuleManager Patch Suite & Example Craft
Because upstream Realism Overhaul does not bundle Tundra Exploration or KRE configs by default, this release includes a complete, **clean-room, MIT-licensed, non-destructive** ModuleManager patch suite under `GameData/kOS-Falcon-GNC/` (zero stock/RO/KRE/Tundra files are overwritten — fully CKAN-compatible). All Layer 1 base RO patches guard with `:HAS[~RSSROConfig[True]]` so they coexist cleanly with any third-party RO pack, while Layer 2 enforces exact GNC calibration parity:

- `Patches/01_RO_Tundra_Falcon9_FH.cfg` — Full RO configs for Falcon 9 Block 4/5, Falcon Heavy, Octaweb/Merlin 1D/MVac (standard & short nozzle), CGT, fairings, and rideshare adapters (cross-verified against the SpaceX Falcon User's Guide Mar 2025 & official RO `Merlin1_Config.cfg`)
- `Patches/02_RO_Tundra_Falcon1_F9v10.cfg` — Full RO configs for Falcon 1 (`Merlin1A`/`1B`/`1C` + `Kestrel`) and Falcon 9 v1.0 (`Bagorah 9`: 9x `Merlin1C` + `Merlin1CVac`)
- `Patches/03_RO_Tundra_LaunchClamps.cfg` — Full RO configs for SLC-40, LC-39A, and SLC-4E Transporter Erectors with cryogenic boiloff & power replenishment
- `Patches/04_RO_Tundra_Dragon.cfg` — Full RO configs for Dragon 1 (`GiganV2`), Crew/Cargo/I4 Dragon 2 (`RodanV2`: 8x SuperDraco, 16x 400 N Draco, PICA-3 heat shield, RealChute 2x drogues + 4x 35 m mains, 2.0 kW trunk solar array), and Dragon XL (`GiganXL`)
- `Patches/05_RO_Tundra_Technologies.cfg` — Optional RO configs for TundraTechnologies (`Haven-1` Gaira station, Iridium NEXT, New Horizons, Starlink dish; guarded by `:NEEDS[TundraTechnologies]`)
- `Patches/06_RO_KRE.cfg` — Full RO configs for all 30 Kerbal Reusability Expansion parts (Aluminum & Titanium Grid Fins, Falcon/Mk2/Aero/Hex/Shepard landing legs, BoosterWing, CGT, KRE SuperDraco/Dragon capsule parts)
- `Patches/07_GNC_FAR_Overrides.cfg` — Layer 2 GNC calibration parity guarantees (`:BEFORE[FerramAerospaceResearch]` FAR conversion for `Grid Fin M Titanium`, 5 deg S1 TVC gimbal, 5 ignitions/TEATEB, interstage separation force, calibrated S1/S2 cold-gas RCS, and UHF RealAntennas)
- `Patches/08_RO_Waterfall.cfg` — Optional Waterfall plume scaling & RO integration (`:NEEDS[Waterfall]`): rescales native TE/TT plumes to 1.48x/1.344x, softens Stage 1 `TE2_19_F9_CGT` cold-gas nitrogen into a realistic translucent mist cone, and adds `ROWaterfall` plumes for single M1D, F9 v1.0 MVac, Dragon 1, KRE SuperDraco/CGT, and TT satellites
- `Textures/{dds,png}/` — Real-world SpaceX / Falcon / Dragon decal textures (derived from [nessux/TundraExploration4RO](https://github.com/nessux/TundraExploration4RO), MIT License)
- `Ships/VAB/Falcon9forRecovery.craft` — Reference Falcon 9 Block 5 craft file

### Optional Mods
- **[ASDS-Manager](https://github.com/tthirteenttt/ASDS-Manager)** — recommended companion mod for automatic `asds_predicted.ks` sync, remote ASDS deployment, and kinematic deck locking
- **RealChute** / **RealAntennas** / **Waterfall** / **NearFutureSolar** — natively supported by the bundled RO patches
- **Trajectories** — visual unpowered impact cross-check
- **Physics Range Extender (PRE)** — keeps ASDS barge loaded at longer ranges
- **BetterTimeWarp** — fully compatible with `lan_window.ks` live `RATELIST` auto-warp

---

## 2. Package Structure & Installation

```text
Release/
├── LICENSE
├── README.md
├── GameData/
│   └── kOS-Falcon-GNC/
│       ├── kOS-Falcon-GNC.version               # KSP-AVC / CKAN version metadata
│       ├── Patches/
│       │   ├── 01_RO_Tundra_Falcon9_FH.cfg      # RO Falcon 9 Block 4/5 & Falcon Heavy
│       │   ├── 02_RO_Tundra_Falcon1_F9v10.cfg   # RO Falcon 1 & Falcon 9 v1.0
│       │   ├── 03_RO_Tundra_LaunchClamps.cfg    # RO Transporter Erector launch clamps
│       │   ├── 04_RO_Tundra_Dragon.cfg          # RO Dragon 1, Dragon 2 & Dragon XL
│       │   ├── 05_RO_Tundra_Technologies.cfg    # Optional RO TundraTechnologies
│       │   ├── 06_RO_KRE.cfg                    # RO Kerbal Reusability Expansion
│       │   ├── 07_GNC_FAR_Overrides.cfg         # FAR Grid Fin & GNC parity overrides
│       │   └── 08_RO_Waterfall.cfg              # Optional RO-scaled Waterfall plumes
│       └── Textures/
│           ├── dds/                             # Falcon 9 / Heavy / F1 decals (MIT)
│           └── png/                             # Bagorah 9 / Dragon / US Flag decals (MIT)
└── Ships/
    ├── Script/                       # kOS Archive root (0:/)
    │   ├── estimate.ks               # [1/3] Pre-flight 3D-RK4 digital twin predictor
    │   ├── ascent.ks                 # [2/3] Stage 1 gravity turn + Stage 2 UPEG insertion
    │   ├── recovery.ks               # [3/3] Stage 1 autonomous ASDS / RTLS recovery
    │   ├── boot/
    │   │   └── falcon9_boot.ks       # Informational menu boot (FMRS-safe, no locks)
    │   ├── config/
    │   │   ├── ascent_config.ks      # Orbit, MECO mass, gravity turn & LAN settings
    │   │   ├── recovery_config.ks    # Recovery mode, landing site & GNC parameters
    │   │   └── asds_predicted.ks     # Auto-generated by estimate.ks
    │   ├── lib/                      # Modular core, physics, nav, guidance, control, HUD
    │   └── vessels/
    │       └── tundra_f9_profile.ks  # Calibrated Falcon 9 hardware & engine specs
    └── VAB/
        └── Falcon9forRecovery.craft  # Reference Falcon 9 Block 5 vessel
```

### Installation Steps
1. Copy `GameData/kOS-Falcon-GNC/` into `<KSP_ROOT>/GameData/` (no existing mod files are overwritten).
2. Copy everything inside `Ships/Script/` directly into `<KSP_ROOT>/Ships/Script/` (this maps to kOS Archive `0:/`).
3. Copy `Ships/VAB/Falcon9forRecovery.craft` into `<KSP_ROOT>/saves/<YourSave>/Ships/VAB/` (or `<KSP_ROOT>/Ships/VAB/`).

---

## 3. Vessel & Staging Requirements

You do **not** have to use the exact bundled `Falcon9forRecovery.craft` (different payloads, fairings, or Dragon capsules are fully supported), **provided that**:
1. **All Stage 1 Merlin 1D engines MUST be configured as `Merlin1D++`** (RealFuels engine config matching `tundra_f9_profile.ks`: 9-eng 7632 kN ASL / 8227 kN Vac, 1-eng 848 kN ASL, 36.1% min throttle) and Stage 2 as `Merlin1DVac+`.
2. **Staging order must follow the same separation structure** as `Falcon9forRecovery.craft`:
   - **Stage 4** (Liftoff — ignited automatically by `ascent.ks`): Stage 1 `Merlin1D++` cluster + Cold Gas Thrusters
   - **Stage 3**: Launch Clamp / Strongback release
   - **Stage 2** (Manual `SPACE` after MECO): Interstage decoupler ONLY — **must be separate from MVac ignition** so `ST_S2_CLEARANCE` executes 2.0 s of RCS ullage and clears the interstage safely
   - **Stage 1** (Auto-staged by `ascent.ks` after clearance): Stage 2 `Merlin1DVac+` + S2 RCS (and fairings if staged manually above 91 km)
   - **Stage 0**: Payload adapter separation
3. Place a kOS CPU on **Stage 2** (for `ascent.ks`) and a kOS CPU on **Stage 1** (for `recovery.ks`).

---

## 4. Standard Mission Workflow (FMRS-Safe)

### Step 1: Configure Mission
- Edit `Ships/Script/config/ascent_config.ks`: set `TARGET_ORBIT` (`PERIAPSIS`, `APOAPSIS`, `INCLINATION`, `LAN_MODE`), `MECO_MASS`, `TARGET_PITCH_END`, and `RECOVERY_MODE` (`"ASDS"` or `"RTLS"`).
  - **Recommended conservative `MECO_MASS` baseline** (excluding launch clamps):
    - **ASDS**: `170 t + payload mass`
    - **RTLS**: `210 t + payload mass`
  - Fine-tune `MECO_MASS` using the Stage 1 fuel margin and Stage 2 delta-V checks printed by `estimate.ks`.
- Edit `Ships/Script/config/recovery_config.ks`: ensure `RECOVERY_MODE` matches `ascent_config.ks`. For ASDS, `LANDING_SITE` reads `0:/config/asds_predicted.ks` automatically; for RTLS, set your landing pad coordinates.

### Step 2: Run Pre-flight Digital Twin (`estimate.ks`)
With the rocket stationary on the launchpad, open any kOS terminal and run:
```kerboscript
SWITCH TO 0.
RUN estimate.
```
- Strips launch clamp mass automatically, integrates coupled 3D-RK4 ascent + entry burn + aero glide + hoverslam, verifies S1 fuel margin, Max-Q, and S2 delta-V margin.
- Automatically writes the optimal ASDS coordinates to `0:/config/asds_predicted.ks`.

### Step 3: Launch & Upper-Stage Insertion (`ascent.ks`)
On the Stage 2 kOS terminal:
```kerboscript
SWITCH TO 0.
RUN ascent.
```
- If `LAN_MODE = "FIXED"`, auto-warps safely to the launch window and cancels warp before ignition.
- Once Stage 1 ignites, **manually press `SPACE` to release the launch tower / clamps as soon as possible** so liftoff timing and fuel burn match `estimate.ks` predictions.
- Executes gravity turn with FAR AoA protection and cuts off at `MECO_MASS`.
- Press `SPACE` to separate Stage 1; Stage 2 automatically performs 2.0 s RCS ullage clearance, ignites MVac, and guides to SECO via closed-loop UPEG.

### Step 4: Booster Recovery (`recovery.ks`)
After SECO, switch back to Stage 1 via **FMRS** and run on the Stage 1 kOS terminal:
```kerboscript
SWITCH TO 0.
RUN recovery.
```
- Fully autonomous flip, RTLS boostback (when in RTLS mode), high-altitude coast, 3-engine entry burn, grid-fin aerodynamic glide (with stowed-deflection lock during ascent & re-arm upon deployment), and single-engine Hoverslam upright touchdown.

---

## 5. Operational Envelope & Known Issues

### Operational Envelope
- **Direct-Insertion Periapsis**: Single-burn UPEG is accurate to `< 1 km` for `PERIAPSIS <= 300 km` (including high-apogee MEO and `200 x 35786 km` GTO). For circular orbits above `300 km`, insert into a `200 x TargetAp` transfer orbit and circularize at apogee.
- **ASDS Barge Deck Elevation**: `ASDS_PROFILE["DECK_ELEVATION"]` defaults to `5.5 m` (calibrated to the ASOG barge at `0.5 m` ocean offset). Set to `0.0` if testing water landings without a barge.
- **External Barge Deployment Mods**: Predicted ASDS coordinates are written to `Ships/Script/config/asds_predicted.ks` (`0:/config/asds_predicted.ks`).

### Known Issues
- **Crew/Cargo Dragon Payloads (`estimate.ks`)**: When launching a Dragon capsule as the payload, the ASDS coordinates predicted by `estimate.ks` are not reliable due to aerodynamic/mass-topology differences from standard fairing stacks. Use **RTLS mode** for Dragon missions (consistent with real-world Dragon flights; no fix is planned).
- **High Gravity Losses on Certain Profiles**: Certain combinations of target inclination and open-loop ascent pitch profile (`TARGET_PITCH_END`, `PITCH_END_ALT`, `PITCH_CURVE_EXP`) can result in higher-than-nominal Stage 2 gravity losses. Adjust `TARGET_PITCH_END` and `MECO_MASS` using `estimate.ks` envelope feedback.
- **High Physics Warp Accuracy Degradation**: Excessive physics warp multipliers (e.g., `3x`–`4x`) can reduce both Stage 1 booster recovery precision and Stage 2 orbital insertion accuracy (and induce structural oscillation on multi-part payloads). Staying within `1x`–`2x` physics warp is recommended (`ascent.ks` also auto-drops physics warp to `1x` if a Stage 2 attitude upset is detected).

---

## 6. Roadmap / Future Plans

- Further reduce Stage 1 cold-gas RCS (Nitrogen) consumption across coast, entry, and glide phases.
- Add an in-game kOS GUI for mission configuration and live telemetry.
- Extend guidance and multi-booster coordination to support **Falcon Heavy**.

---

## 7. License & Credits

- Released under the **MIT License** (see [LICENSE](LICENSE)).
- Clean-room Realism Overhaul & FAR ModuleManager patches target **Tundra Exploration** (by Damonvv), **Tundra Technologies**, **Kerbal Reusability Expansion (KRE)** (by EmbersArc), **Realism Overhaul**, and **Ferram Aerospace Research Continued** without overwriting any upstream mod files.
- Bundled SpaceX / Falcon / Dragon decal textures in `GameData/kOS-Falcon-GNC/Textures/` are modified from **[nessux/TundraExploration4RO](https://github.com/nessux/TundraExploration4RO)** under the **MIT License**.
- Developed with assistance from **Google Gemini** for GNC modeling, aerospace data verification, ModuleManager patching, and documentation.
