// ============================================================================
// Ascent & Upper-Stage UPEG Guidance Configuration (ascent_config.ks)
// ----------------------------------------------------------------------------
// Default mission template: Cape Canaveral 28.6 deg LEO (200x200 km) ASDS.
// After editing parameters, run "SWITCH TO 0. RUN estimate." on the pad.
// ============================================================================

SET ASCENT_CONFIG TO LEXICON(
    // 1. Target total stack SHIP:MASS at MECO (metric tons, excluding launch clamps).
    //    Verify S1 fuel margin and S2 delta-V margin via estimate.ks.
    "MECO_MASS", 180.0,

    // 2. Minimum altitude (m ASL) required before MECO can trigger.
    "MIN_MECO_ALT", 40000.0,

    // 3. Stage 2 closed-loop UPEG target orbit.
    //    Note: Single-burn direct insertion is accurate for PERIAPSIS <= 300 km.
    //    For higher circular orbits, use a 200 x TargetAp transfer orbit.
    "TARGET_ORBIT", LEXICON(
        "PERIAPSIS", 200000.0,         // Target periapsis altitude (m)
        "APOAPSIS", 200000.0,          // Target apoapsis altitude (m, >= PERIAPSIS)
        "INCLINATION", 28.6,           // Target inclination (deg, >= |launch_lat|; >90 for retrograde SSO)
        "LAN_MODE", "IGNORE",          // "IGNORE": launch immediately; "FIXED": wait for LAN window & lock plane
        "LAN", 0.0,                    // Target longitude of ascending node (deg, 0..360; FIXED mode only)
        "LAN_LEAD_TIME", 150.0,        // Launch lead compensation for Earth rotation during ascent (s)
        "AUTO_WARP", TRUE              // TRUE: auto rails-warp & stop; FALSE: manual warp with auto-stop
    ),

    // 4. Stage 1 open-loop gravity turn profile (with dynamic-Q AoA limiting for FAR).
    "ASCENT_PROFILE", LEXICON(
        "PITCH_START_ALT", 250.0,      // Radar altitude (m) to begin pitchover (requires Vz > 45 m/s)
        "PITCH_END_ALT", 52000.0,      // Altitude (m ASL) where pitch curve reaches TARGET_PITCH_END
        "TARGET_PITCH_END", 24.0,      // Terminal pitch angle (deg; ~24 for ASDS, ~28-32 for RTLS)
        "PITCH_CURVE_EXP", 0.50,       // Power-law exponent (<1 pitches over earlier)
        "MAX_AOA_DEG", 5.0,            // Reference AoA limit (deg) scaled dynamically above 2.5 kPa
        "AUTO_IGNITE", TRUE,           // TRUE: script throttles up and stages liftoff automatically
        "IGNITION_WAIT", 0.5,          // Hold time (s) after liftoff stage command
        "USE_TARGET_AZIMUTH", TRUE,    // TRUE: solve 3D launch azimuth from TARGET_ORBIT; FALSE: use MANUAL_AZIMUTH
        "MANUAL_AZIMUTH", 90.0,        // Compass heading (deg) when USE_TARGET_AZIMUTH is FALSE
        "LAUNCH_SOUTH", "AUTO"         // "AUTO" / "NEAREST" (FIXED LAN) / TRUE (south) / FALSE (north)
    ),

    // 5. Stage separation & MVac interstage clearance sequence.
    //    Keep interstage decoupler and MVac ignition in separate stages.
    "STAGING", LEXICON(
        "STAGE_MASS_DROP", 20.0,       // Mass drop (t) threshold confirming physical stage separation
        "UPPER_STAGE_MIN_MASS", 60.0,  // Mass threshold (t) distinguishing S2 from S1 after separation
        "S2_CLEARANCE_WAIT", 2.0,      // RCS ullage & nozzle-clearance duration (s) before MVac ignition
        "S2_IGNITION_STAGE", TRUE,     // TRUE: script issues STAGE to ignite MVac after clearance
        "S2_IGNITION_WAIT", 1.2,       // Spool-up hold (s) after MVac ignition before starting UPEG
        "FAIRING_REMINDER_ALT", 91000.0, // Altitude (m) to print manual fairing deployment reminder
        "STAGING_TIMEOUT", 120.0       // Safety timeout (s) waiting for manual separation after MECO
    ),

    // 6. Stage 2 UPEG safety burn-time cap (s).
    "UPEG", LEXICON(
        "MAX_BURN_TIME", 600.0
    ),

    // 7. Recovery mode ("ASDS" or "RTLS") — keep aligned with config/recovery_config.ks.
    "RECOVERY_MODE", "ASDS",
    "FALLBACK_RESERVE_ON", TRUE,       // Force MECO if S1 propellant hits recovery reserve floor

    // 8. Overall ascent script runtime guard (s).
    "MAX_ASCENT_TIME", 750.0
).
