// ============================================================================
// kOS-BoosterRecovery - Falcon 9 Bootloader (Informational Menu Only)
// ----------------------------------------------------------------------------
// FMRS-safe design: never auto-runs flight scripts or holds control locks.
// All entry scripts run cleanly from Archive (0:/):
//     SWITCH TO 0.
//     RUN estimate.
//     RUN ascent.
//     RUN recovery.
// ============================================================================

CLEARSCREEN.
PRINT "--------------------------------------------------".
PRINT " [BOOT] Falcon 9 Recovery Autopilot - READY      ".
PRINT " Target: Tundra Exploration Ghidorah 9 (RO/FAR)  ".
PRINT "--------------------------------------------------".
PRINT " FMRS-Safe Decoupled Workflow (SWITCH TO 0.)     ".
PRINT "--------------------------------------------------".
PRINT " [1] Pre-flight Digital Twin : RUN estimate.     ".
PRINT " [2] Ascent + S2 UPEG Orbit  : RUN ascent.       ".
PRINT " [3] Stage 1 Booster Landing : RUN recovery.     ".
PRINT "--------------------------------------------------".

IF EXISTS("0:/config/ascent_config.ks") AND EXISTS("0:/config/recovery_config.ks") {
    PRINT " [BOOT] Archive (0:/) config files verified OK.  ".
} ELSE {
    PRINT " [BOOT ERROR] Missing 0:/config/*.ks on Archive! ".
}
