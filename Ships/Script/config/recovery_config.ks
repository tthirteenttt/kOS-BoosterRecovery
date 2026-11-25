// ============================================================================
// Stage 1 Booster Recovery Guidance Configuration (recovery_config.ks)
// ----------------------------------------------------------------------------
// Default mission template: ASDS barge recovery using 0:/config/asds_predicted.ks.
// For RTLS: set RECOVERY_MODE to "RTLS" and update LANDING_SITE coordinates.
// ============================================================================
RUNONCEPATH("0:/config/asds_predicted.ks").

SET RECOVERY_CONFIG TO LEXICON(
    // Recovery mode: "ASDS" (downrange drone ship) or "RTLS" (return to launch site).
    // Must match RECOVERY_MODE in config/ascent_config.ks.
    "RECOVERY_MODE", "ASDS",

    // Landing target coordinates (ASDS reads estimate.ks output; replace with pad coords for RTLS).
    "LANDING_SITE", LEXICON(
        "LATITUDE", PREDICTED_ASDS_LAT,  // Target latitude (deg); auto-populated by estimate.ks
        "LONGITUDE", PREDICTED_ASDS_LNG, // Target longitude (deg); auto-populated by estimate.ks
        "ELEVATION", 0.0                 // Optional manual elevation floor (m ASL); barge height is in ASDS_PROFILE
    ),

    // FSM entry state: "AUTO" selects based on live altitude and vertical speed.
    "INITIAL_STATE", "AUTO",

    // Altitude thresholds (m ASL) used by INITIAL_STATE = "AUTO".
    "STATE_THRESHOLDS", LEXICON(
        "FLIP_MIN_ALT", 60000.0,
        "COAST_MIN_ALT", 55000.0,
        "ENTRY_MIN_ALT", 40000.0,
        "GLIDE_MIN_ALT", 2500.0
    ),

    // Shared recovery burn & touchdown parameters (mode profiles override EB fields).
    "GUIDANCE", LEXICON(
        "COAST_ENTRY_ALT", 68000.0,    // Default entry burn interface altitude (m ASL)
        "ENTRY_BURN_END_ALT", 36000.0, // Hard lower altitude limit (m ASL) for entry burn cutoff
        "ENTRY_BURN_END_SPEED", 700.0, // Default entry burn lower speed floor (m/s)
        "ENTRY_BURN_THROTTLE", 0.90,   // Nominal 3-engine entry burn throttle command
        "HOVERSLAM_MARGIN", 30.0,      // Additional altitude margin (m) on hoverslam ignition trigger
        "LANDING_THROTTLE_MAX", 0.98,  // Maximum throttle command during terminal hoverslam
        "LEGS_DEPLOY_ALT", 180.0,      // Radar altitude (m) to extend landing legs
        "TOUCHDOWN_ALT", 0.5           // Radar altitude (m) cutoff threshold above target deck/pad
    ),

    // RK4 trajectory impact predictor parameters (calibrated to RO/FAR F9 Block 5).
    "PREDICTOR", LEXICON(
        "MAX_STEPS", 160,              // Base RK4 step budget (expanded automatically when SIM_HS=TRUE)
        "DT", 3.5,                     // Base integration timestep (s)
        "ATM_TOP", 140000.0,           // Atmospheric cutoff altitude (m)
        "DRAG_CD", 3.12,               // Calibrated unpowered supersonic base Cd (S_ref = 8.25 m^2)
        "DRAG_AREA", 8.25,             // FAR aerodynamic reference area (m^2)
        "ROTATION_SIGN", -1.0,         // Planet rotation sign for body-fixed impact projection
        "MIN_ALT", 0.0,                // Base impact surface altitude (m ASL)
        "UPDATE_PERIOD", 0.5           // Nominal predictor refresh interval (s)
    ),

    // Aerodynamic grid-fin glide guidance defaults (overridden by ASDS/RTLS profiles).
    "AERO", LEXICON(
        "MAX_AOA_DEG", 16.0,           // Nominal maximum glide AoA command (deg)
        "Q_SCALE_KPA", 0.0,            // Optional extra high-Q gain attenuation (0.0 = disabled)
        "AUTH_MIN_M", 120.0,           // Lower clamp on remaining glide authority normalization (m)
        "AUTH_MAX_M", 2000.0,          // Upper clamp on remaining glide authority normalization (m)
        "HANDOFF_OVERSHOOT_M", 15.0,   // Slight downrange handoff bias (m) for monotonic landing pitch-up
        "DOWN_KP", 22.0,
        "DOWN_KI", 0.0,
        "DOWN_KD", 0.0,
        "CROSS_KP", 22.0,
        "CROSS_KI", 0.0,
        "CROSS_KD", 0.0,
        "STEER_SLEW_ALPHA", 0.2,       // Low-pass filter alpha (referenced to 50 Hz dt = 0.02 s)
        "DEADBAND_M", 2.0,             // Horizontal miss deadband (m)
        "MIN_Q_FOR_GLIDE", 0.003,      // Minimum dynamic pressure (atm) to enable aero steering
        "RCS_Q_CUTOFF", 0.20           // Dynamic pressure (atm) above which glide RCS turns off
    ),

    // Terminal Hoverslam guidance parameters (calibrated from in-game FAR flight data).
    "LANDING_ATTITUDE", LEXICON(
        "CN_ALPHA_LAND", 3.9,          // Measured powered subsonic normal-force slope (1/rad)
        "CD_POWERED", 0.14,            // Measured retropropulsion axial drag coefficient
        "MAX_TILT_DEG", 32.0,          // High-altitude zenith tilt cap (deg; tapers smoothly to 0 deg)
        "MAX_AOA_DEG", 20.0,           // Maximum AoA around retrograde under high dynamic pressure (deg)
        "POLARITY_MIN_ETA", 0.10,      // Net TVC-over-aero polarity margin threshold to wake lateral guidance
        "POLARITY_FULL_ETA", 0.35,     // Polarity margin for full lateral authority
        "ALIGN_GATE_ALT", 28.0,        // Radar altitude (m) to finish centering & velocity nulling
        "UPRIGHT_LOCK_ALT", 12.0,      // Radar altitude (m) below which attitude locks strictly vertical
        "VEL_TAU_S", 1.05,             // Horizontal velocity inner-loop time constant (s)
        "FLARE_TAU_S", 1.8,            // Near-target exponential braking time constant (s)
        "HANDOFF_OVERSHOOT_M", 15.0
    ),

    // kOS SteeringManager aerodynamic glide defaults.
    "STEERING_MANAGER", LEXICON(
        "MAX_STOPPING_TIME", 2.0,
        "PITCH_TS", 1.6,
        "YAW_TS", 1.6,
        "ROLL_TS", 3.0,
        "PID_KD", 1.0,
        "TORQUE_EPSILON_MAX", 0.005,
        "ROLL_CONTROL_ANGLE_RANGE", -1.0
    ),

    // Hardware actuator identifiers (Tundra F9 + KRE).
    "ACTUATORS", LEXICON(
        "ENGINE_MODE_AT_START", 0,     // 0=AllEngines, 1=ThreeLanding, 2=CenterOnly
        "GRIDFIN_EVENT_KEYWORD", "Extend",
        "GRIDFIN_PART_KEYWORD", "Grid Fin",
        "LEG_PART_KEYWORD", "FalconLeg",
        "LEG_EVENT_KEYWORD", "Extend"
    ),

    // Runtime safety limits.
    "SAFETY", LEXICON(
        "MAX_FLIGHT_TIME", 900.0,
        "KOS_IPU", 2000,
        "RESTORE_IPU", TRUE
    ),

    // ASDS mission profile overrides.
    "ASDS_PROFILE", LEXICON(
        "DECK_ELEVATION", 5.5,         // ASOG barge deck height (m ASL); set 0.0 for bare ocean landing
        "COAST_ENTRY_ALT", 68000.0,
        "COAST_PITCH_DEG", 25.0,
        "EB_END_SPEED", 800.0,
        "EB_MAX_SAFE_SPEED", 1250.0,
        "EB_TAILOFF_TAU_S", 0.35,
        "EB_MIN_LANDING_PROP_T", 4.6,
        "GLIDE_RCS_Q_CUTOFF", 0.20,
        "USE_AUTH_NORM", TRUE,
        "Q_SCALE_KPA", 0.0,
        "AUTH_MIN_M", 120.0,
        "AUTH_MAX_M", 2000.0,
        "HANDOFF_OVERSHOOT_M", 15.0,
        "GLIDE_DOWN_KP", 22.0,
        "GLIDE_CROSS_KP", 22.0,
        "GLIDE_MAX_AOA", 16.0,
        "GLIDE_PRED_DT", 2.0,
        "GLIDE_PRED_STEPS", 240
    ),

    // RTLS mission profile overrides.
    "RTLS_PROFILE", LEXICON(
        "DECK_ELEVATION", 0.0,
        "COAST_ENTRY_ALT", 58000.0,
        "COAST_PITCH_DEG", 62.0,
        "BB_AIM_EB_END_SPEED", 750.0,
        "EB_END_SPEED", 700.0,
        "EB_MAX_SAFE_SPEED", 1050.0,
        "EB_TAILOFF_TAU_S", 0.35,
        "EB_MIN_LANDING_PROP_T", 4.6,
        "GLIDE_RCS_Q_CUTOFF", 0.25,
        "USE_AUTH_NORM", TRUE,
        "Q_SCALE_KPA", 0.0,
        "AUTH_MIN_M", 120.0,
        "AUTH_MAX_M", 2000.0,
        "HANDOFF_OVERSHOOT_M", 15.0,
        "GLIDE_DOWN_KP", 22.0,
        "GLIDE_CROSS_KP", 22.0,
        "GLIDE_MAX_AOA", 16.5,
        "GLIDE_PRED_DT", 2.0,
        "GLIDE_PRED_STEPS", 240
    )
).
