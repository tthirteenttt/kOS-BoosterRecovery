// ============================================================================
// [1/3] Pre-flight 3D-RK4 Digital Twin Predictor (estimate.ks)
// ----------------------------------------------------------------------------
// Usage (stationary on launchpad):
//     SWITCH TO 0.
//     RUN estimate.
//
// Reads  : config/ascent_config.ks, config/recovery_config.ks,
//          vessels/tundra_f9_profile.ks
// Outputs: MECO state, optimal ASDS coordinates (0:/config/asds_predicted.ks),
//          and fuel / aero / glide / S2 delta-V envelope checks.
// ============================================================================

RUNONCEPATH("0:/vessels/tundra_f9_profile.ks").
RUNONCEPATH("0:/lib/core/math.ks").
RUNONCEPATH("0:/lib/core/logger.ks").
RUNONCEPATH("0:/lib/physics/aero_atmo.ks").
RUNONCEPATH("0:/lib/guidance/lan_window.ks").
RUNONCEPATH("0:/lib/guidance/predictor_rk4.ks").
RUNONCEPATH("0:/lib/guidance/asds_calculator.ks").
RUNPATH("0:/config/ascent_config.ks").
RUNPATH("0:/config/recovery_config.ks").

CLEARSCREEN.
log_info("SIM", "==========================================================").
log_info("SIM", "  Falcon 9 Pre-flight 3D-RK4 Digital Twin Predictor       ").
log_info("SIM", "==========================================================").

IF SHIP:ALTITUDE > 1000.0 OR SHIP:VELOCITY:SURFACE:MAG > 5.0 {
    log_warn("SIM", "Run this script while stationary on the launchpad!").
}

LOCAL old_ipu IS CONFIG:IPU.
SET CONFIG:IPU TO 2000.
LOCAL t_wall_start IS TIME:SECONDS.

log_info("SIM", "Integrating: Liftoff RK4 -> MECO -> Entry Burn -> Landing...").

// Optional third arg drag_scale (default 1.00) scales ascent drag
LOCAL sim IS run_preflight_asds_digital_twin(ASCENT_CONFIG, RECOVERY_CONFIG, 1.00).

LOCAL t_wall_elapsed IS TIME:SECONDS - t_wall_start.
SET CONFIG:IPU TO old_ipu.

LOCAL veh IS sim["VEH"].
LOCAL asc IS sim["ASC"].
LOCAL desc IS sim["DESC"].
LOCAL asds_geo IS desc["ASDS_GEO"].
LOCAL tgt_orbit IS ASCENT_CONFIG["TARGET_ORBIT"].
LOCAL branch_str IS "North (Asc)".
IF sim["GO_SOUTH"] { SET branch_str TO "South (Desc)". }

PRINT " ".
log_info("VEH", "------------------ Vehicle Mass Topology -----------------").
log_info("VEH", "Clamp Mass   : " + ROUND(veh["TOWER_MASS"], 1) + " t | Pure Rocket Mass: " + ROUND(veh["PAD_PURE_MASS"], 2) + " t").
log_info("VEH", "S1 Wet / Dry : " + ROUND(veh["S1_WET_MASS"], 2) + " / " + ROUND(veh["S1_DRY_MASS"], 2) + " t (Detected: " + veh["TOPOLOGY_OK"] + ")").
log_info("VEH", "S2+PL Wet/Dry: " + ROUND(veh["S2_WET_MASS"], 2) + " / " + ROUND(veh["S2_DRY_MASS"], 2) + " t").

PRINT " ".
log_info("MECO", "------------------ Ascent MECO Prediction ----------------").
log_info("MECO", "Target Orbit : " + ROUND(tgt_orbit["PERIAPSIS"]/1000.0, 1) + " x " + ROUND(tgt_orbit["APOAPSIS"]/1000.0, 1) + " km @ " + ROUND(tgt_orbit["INCLINATION"], 2) + " deg").
log_info("MECO", "Azimuth      : " + ROUND(sim["AZIMUTH_DEG"], 2) + " deg (" + branch_str + ")").
log_info("MECO", "MECO T / Alt : T+" + ROUND(asc["T_MECO"], 1) + " s | " + ROUND(asc["H_MECO"]/1000.0, 2) + " km (Apogee " + ROUND(desc["MAX_ALT_M"]/1000.0, 1) + " km)").
log_info("MECO", "MECO Vel/FPA : Orb " + ROUND(asc["V_MECO_ORB"], 1) + " m/s | Air " + ROUND(asc["V_MECO_AIR"], 1) + " m/s @ " + ROUND(asc["FPA_MECO"], 1) + " deg").
log_info("MECO", "S1 Sep Mass  : " + ROUND(asc["BOOSTER_SEP_T"], 2) + " t (Stack MECO " + ROUND(asc["MECO_MASS_T"], 2) + " t)").

PRINT " ".
log_info("ASDS", "=============== Optimal ASDS Coordinates =================").
log_info("ASDS", "Downrange    : " + ROUND(sim["DOWNRANGE_KM"], 1) + " km | Flight Time: " + ROUND(desc["TOTAL_TIME"], 0) + " s").
log_info("ASDS", "ASDS Lat     : " + ROUND(asds_geo:LAT, 6) + " deg").
log_info("ASDS", "ASDS Lng     : " + ROUND(asds_geo:LNG, 6) + " deg").

PRINT " ".
log_info("ENV", "----------------- Mission Envelope Checks ----------------").
log_info("ENV", "S1 Prop Split: EB " + ROUND(sim["EB_FUEL_T"], 2) + " t | Landing " + ROUND(sim["LAND_FUEL_T"], 2) + " t (dV " + ROUND(sim["DV_LAND_EST"], 0) + " m/s)").
IF sim["FUEL_OK"] {
    log_info("ENV", "[GO]    S1 Margin : " + ROUND(sim["FUEL_MARGIN_T"], 2) + " t remaining at touchdown").
} ELSE IF sim["FUEL_MARGIN_T"] > 1.0 {
    log_warn("ENV", "[WARN]  S1 Margin : " + ROUND(sim["FUEL_MARGIN_T"], 2) + " t (tight; consider higher MECO_MASS)").
} ELSE {
    log_warn("ENV", "[NO-GO] S1 Margin : " + ROUND(sim["FUEL_MARGIN_T"], 2) + " t (insufficient; increase MECO_MASS)").
}

IF sim["AERO_OK"] {
    log_info("ENV", "[GO]    Aero Load : Max-Q " + ROUND(desc["MAX_Q_KPA"], 1) + " kPa | Peak " + ROUND(desc["MAX_G"], 2) + " G").
} ELSE {
    log_warn("ENV", "[WARN]  Aero Load : Max-Q " + ROUND(desc["MAX_Q_KPA"], 1) + " kPa | Peak " + ROUND(desc["MAX_G"], 2) + " G (steep)").
}

log_info("ENV", "[GO]    Glide Env : Reachable radius +/-" + ROUND(desc["GLIDE_RADIUS_M"]/1000.0, 2) + " km (V@3km " + ROUND(desc["V_3KM"], 0) + " m/s)").
IF ASCENT_CONFIG["RECOVERY_MODE"] <> "RTLS" {
    log_info("ENV", "EB Window    : Width " + ROUND(sim["EB_WINDOW_KM"], 2) + " km | Nom Cutoff " +
                    ROUND(sim["EB_NOM_SPD"], 0) + " m/s (Near " + ROUND(sim["EB_NEAR_ALT_KM"], 1) +
                    " km / " + ROUND(sim["EB_NEAR_SPD"], 0) + " m/s)").
    IF sim["EB_WINDOW_KM"] < 3.0 {
        log_warn("ENV", "[WARN] Narrow entry burn window (<3 km); consider lowering TARGET_PITCH_END.").
    }
}

IF sim["S2_OK"] {
    log_info("ENV", "[GO]    S2 Delta-V: Req " + ROUND(sim["S2_DV_REQ"], 0) + " / Avail " + ROUND(sim["S2_DV_AVAIL"], 0) + " m/s (+" + ROUND(sim["S2_DV_MARGIN"], 0) + " m/s)").
} ELSE {
    log_warn("ENV", "[NO-GO] S2 Delta-V: Req " + ROUND(sim["S2_DV_REQ"], 0) + " / Avail " + ROUND(sim["S2_DV_AVAIL"], 0) + " m/s (" + ROUND(sim["S2_DV_MARGIN"], 0) + " m/s; lower MECO_MASS)").
}

// Export predicted ASDS coordinates for recovery_config.ks and external barge tools
LOCAL out_file IS "0:/config/asds_predicted.ks".
IF EXISTS(out_file) { DELETEPATH(out_file). }
LOG "// Auto-generated by estimate.ks (3D-RK4 Digital Twin)" TO out_file.
LOG "GLOBAL PREDICTED_ASDS_LAT IS " + ROUND(asds_geo:LAT, 6) + "." TO out_file.
LOG "GLOBAL PREDICTED_ASDS_LNG IS " + ROUND(asds_geo:LNG, 6) + "." TO out_file.

PRINT " ".
log_info("SIM", "Done in " + ROUND(t_wall_elapsed, 2) + " s. Coordinates written to 0:/config/asds_predicted.ks.").
