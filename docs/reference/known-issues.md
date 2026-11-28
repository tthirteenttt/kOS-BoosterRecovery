---
title: Envelope, Known Issues & Roadmap
nav_order: 5
---

# Operational Envelope, Known Issues & Roadmap

## Operational Envelope

- **Direct-Insertion Periapsis**: Single-burn closed-loop UPEG is accurate to `< 1 km` for `PERIAPSIS <= 300 km` (including high-apogee MEO and `200 x 35786 km` GTO). For higher circular orbits, insert into a `200 x TargetAp` transfer orbit and circularize at apogee.
- **ASDS Barge Deck Elevation**: `ASDS_PROFILE["DECK_ELEVATION"]` defaults to `5.5 m` (calibrated to the ASOG barge at `0.5 m` ocean offset). Set it to `0.0` when testing water landings without a barge.
- **External Barge Deployment**: Predicted ASDS coordinates are written to `Ships/Script/config/asds_predicted.ks` (`0:/config/asds_predicted.ks`) for seamless integration with [ASDS-Manager](https://github.com/tthirteenttt/ASDS-Manager).

---

## Known Issues

- **Crew/Cargo Dragon Payloads (`estimate.ks`)**: When launching a Dragon capsule as the payload, the ASDS coordinates predicted by `estimate.ks` are not reliable due to aerodynamic and mass-topology differences from standard fairing stacks. Use **RTLS mode** for Dragon missions (consistent with real-world Dragon flights; no fix is planned).
- **High Gravity Losses on Certain Ascent Profiles**: Certain combinations of target inclination and open-loop ascent pitch profile (`TARGET_PITCH_END`, `PITCH_END_ALT`, `PITCH_CURVE_EXP`) can result in higher-than-nominal Stage 2 gravity losses. Adjust `TARGET_PITCH_END` and `MECO_MASS` using `estimate.ks` envelope feedback.
- **High Physics Warp Accuracy Degradation**: Excessive physics warp multipliers (e.g., `3x`–`4x`) can reduce both Stage 1 booster recovery precision and Stage 2 orbital insertion accuracy (and induce structural oscillation on multi-part payloads). Staying within `1x`–`2x` physics warp is recommended (`ascent.ks` also auto-drops physics warp to `1x` if a Stage 2 attitude upset is detected).

---

## Roadmap

- Further optimize Stage 1 cold-gas RCS (Nitrogen) consumption across coast, entry, and glide phases.
- Add an in-game kOS GUI for mission configuration and live telemetry.
- Extend guidance and multi-booster coordination to support **Falcon Heavy**.
