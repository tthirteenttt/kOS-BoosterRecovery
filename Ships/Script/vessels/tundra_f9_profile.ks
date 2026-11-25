// ============================================================================
// Tundra Exploration Falcon 9 Block 5 (Ghidorah 9) Hardware Profile
// ----------------------------------------------------------------------------
// Calibrated from RO_TE_Falcon_9.cfg, RO_KRE.cfg, and in-game FAR telemetry.
// Requires Stage 1 Merlin1D++ and Stage 2 Merlin1DVac+ engine configs.
// ============================================================================

GLOBAL TUNDRA_F9_PROFILE IS LEXICON(
    // Geometry & mass parameters
    "VESSEL_NAME", "Falcon 9 Block 5 (Ghidorah 9)",
    "LANDING_GEAR_OFFSET", 43.5,       // Interstage root part to extended leg footpads (m)
    "REFERENCE_AREA", 10.75,           // Nominal cross-sectional area (m^2; FAR S_ref = 8.25 m^2)
    "S1_DRY_MASS", 22.2,               // Stage 1 dry mass (t)
    "S2_DRY_MASS", 4.5,                // Stage 2 dry mass (t)
    "S1_FUEL_VOLUME", 397159.68,       // Stage 1 total cryogenic propellant volume (L)
    "S2_FUEL_VOLUME", 101325.00,       // Stage 2 total cryogenic propellant volume (L)

    // RealFuels Merlin 1D++ / Merlin 1DVac+ engine specifications
    "ENGINES", LEXICON(
        "ALL", LEXICON(
            "NAME", "AllEngines",
            "INDEX", 0,
            "COUNT", 9,
            "MAX_THRUST_VAC", 8227.08, // kN
            "MAX_THRUST_ASL", 7632.00, // kN
            "MIN_THRUST_VAC", 2970.00, // kN
            "MIN_THROTTLE", 0.361,
            "ISP_VAC", 311.0,
            "ISP_ASL", 288.5
        ),
        "THREE", LEXICON(
            "NAME", "ThreeLanding",
            "INDEX", 1,
            "COUNT", 3,
            "MAX_THRUST_VAC", 2742.36, // kN
            "MAX_THRUST_ASL", 2544.00, // kN
            "MIN_THRUST_VAC", 990.00,  // kN
            "MIN_THROTTLE", 0.361,
            "ISP_VAC", 311.0,
            "ISP_ASL", 288.5
        ),
        "CENTER", LEXICON(
            "NAME", "CenterOnly",
            "INDEX", 2,
            "COUNT", 1,
            "MAX_THRUST_VAC", 914.12,  // kN
            "MAX_THRUST_ASL", 848.00,  // kN
            "MIN_THRUST_VAC", 330.00,  // kN
            "MIN_THROTTLE", 0.361,
            "ISP_VAC", 311.0,
            "ISP_ASL", 288.5
        ),
        "S2_VAC", LEXICON(
            "NAME", "Merlin1DVac+",
            "MAX_THRUST_VAC", 981.00,  // kN
            "MIN_THROTTLE", 0.40,
            "ISP_VAC", 348.0
        )
    ),

    // Aerodynamic & actuator defaults
    "GRIDFIN_ACTION_GROUP", "Brakes",
    "LANDING_LEG_ACTION_GROUP", "Gear",
    "GRIDFIN_MAX_DEFLECTION", 35.0,
    "MAX_ALLOWED_AOA", 14.0,
    "RCS_THRUST_PER_POD", 10.0,

    // Terminal touchdown parameters
    "TOUCHDOWN_VELOCITY", -1.2,        // Target vertical touchdown speed (m/s)
    "LEGS_DEPLOY_ALTITUDE", 160.0
).
