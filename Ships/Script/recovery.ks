// ============================================================================
// [3/3] Booster Recovery Guidance Entry (recovery.ks) v1.0 —— Release
// Usage: SWITCH TO 0. RUN recovery.
// ============================================================================

RUNONCEPATH("0:/vessels/tundra_f9_profile.ks").
RUNONCEPATH("0:/lib/core/math.ks").
RUNONCEPATH("0:/lib/core/fsm.ks").
RUNONCEPATH("0:/lib/core/logger.ks").
RUNONCEPATH("0:/lib/physics/aero_atmo.ks").
RUNONCEPATH("0:/lib/nav/state_estimator.ks").
RUNONCEPATH("0:/lib/guidance/predictor_rk4.ks").
RUNONCEPATH("0:/lib/guidance/boostback_guide.ks").
RUNONCEPATH("0:/lib/guidance/aero_guide.ks").
RUNONCEPATH("0:/lib/guidance/hoverslam_guide.ks").
RUNONCEPATH("0:/lib/control/pid_controller.ks").
RUNONCEPATH("0:/lib/control/rcs_controller.ks").
RUNONCEPATH("0:/lib/control/engine_manager.ks").
RUNONCEPATH("0:/lib/control/gridfin_mixer.ks").
RUNONCEPATH("0:/lib/control/steering_manager.ks").
RUNONCEPATH("0:/lib/telemetry/hud_display.ks").
RUNPATH("0:/config/recovery_config.ks").

// Compute live usable bipropellant mass (t), immune to LOX boil-off or residual RP-1
FUNCTION get_usable_main_prop_mass {
    LOCAL ox_m IS 0.0.
    LOCAL ox_cap_m IS 0.0.
    LOCAL fu_m IS 0.0.
    LOCAL fu_cap_m IS 0.0.
    FOR res IN SHIP:RESOURCES {
        LOCAL rname IS res:NAME.
        IF rname:CONTAINS("Oxy") {
            SET ox_m TO ox_m + res:AMOUNT * res:DENSITY.
            SET ox_cap_m TO ox_cap_m + res:CAPACITY * res:DENSITY.
        } ELSE IF rname:CONTAINS("RP-1") OR rname:CONTAINS("Kerosene") OR rname:CONTAINS("LiquidFuel") {
            SET fu_m TO fu_m + res:AMOUNT * res:DENSITY.
            SET fu_cap_m TO fu_cap_m + res:CAPACITY * res:DENSITY.
        }
    }
    IF ox_cap_m > 0.1 AND fu_cap_m > 0.1 {
        LOCAL ox_frac IS ox_cap_m / (ox_cap_m + fu_cap_m).
        LOCAL fu_frac IS fu_cap_m / (ox_cap_m + fu_cap_m).
        RETURN MIN(ox_m / ox_frac, fu_m / fu_frac).
    }
    RETURN MAX(0.0, ox_m + fu_m).
}

FUNCTION choose_recovery_initial_state {
    PARAMETER cfg.
    LOCAL th IS cfg["STATE_THRESHOLDS"].
    LOCAL entry_alt IS SHIP:ALTITUDE.
    LOCAL vs IS SHIP:VERTICALSPEED.

    IF vs > 0.0 OR (entry_alt >= th["FLIP_MIN_ALT"] AND vs > -100.0) {
        RETURN "ST_FLIP".
    }
    IF entry_alt >= th["COAST_MIN_ALT"] {
        RETURN "ST_COAST".
    }
    IF entry_alt >= th["ENTRY_MIN_ALT"] {
        RETURN "ST_ENTRY_BURN".
    }
    IF entry_alt >= th["GLIDE_MIN_ALT"] {
        RETURN "ST_AERO_GLIDE".
    }
    RETURN "ST_LANDING_BURN".
}

FUNCTION resolve_mode_profile {
    PARAMETER cfg, mode_name.
    IF mode_name = "RTLS" {
        IF cfg:HASKEY("RTLS_PROFILE") { RETURN cfg["RTLS_PROFILE"]:COPY. }
        RETURN LEXICON(
            "DECK_ELEVATION", 0.0,
            "COAST_ENTRY_ALT", 58000.0,
            "COAST_PITCH_DEG", 62.0,
            "BB_AIM_EB_END_SPEED", 750.0,
            "EB_END_SPEED", 700.0,
            "EB_MAX_SAFE_SPEED", 1050.0,
            "EB_TAILOFF_TAU_S", 0.35,
            "EB_MIN_LANDING_PROP_T", 4.6,
            "GLIDE_RCS_Q_CUTOFF", 0.09,
            "GLIDE_PRED_DT", 2.0,
            "GLIDE_PRED_STEPS", 240,
            "USE_AUTH_NORM", TRUE,
            "Q_SCALE_KPA", 0.0,
            "AUTH_MIN_M", 120.0,
            "AUTH_MAX_M", 2000.0,
            "HANDOFF_OVERSHOOT_M", 15.0,
            "GLIDE_DOWN_KP", 22.0,
            "GLIDE_CROSS_KP", 22.0,
            "GLIDE_MAX_AOA", 16.5
        ).
    }
    IF cfg:HASKEY("ASDS_PROFILE") { RETURN cfg["ASDS_PROFILE"]:COPY. }
    RETURN LEXICON(
        "DECK_ELEVATION", 5.5,
        "COAST_ENTRY_ALT", cfg["GUIDANCE"]["COAST_ENTRY_ALT"],
        "COAST_PITCH_DEG", 25.0,
        "BB_AIM_EB_END_SPEED", 800.0,
        "EB_END_SPEED", 800.0,
        "EB_MAX_SAFE_SPEED", 1250.0,
        "EB_TAILOFF_TAU_S", 0.35,
        "EB_MIN_LANDING_PROP_T", 4.6,
        "USE_AUTH_NORM", TRUE,
        "Q_SCALE_KPA", 0.0,
        "AUTH_MIN_M", 120.0,
        "AUTH_MAX_M", 2000.0,
        "HANDOFF_OVERSHOOT_M", 15.0,
        "GLIDE_DOWN_KP", 22.0,
        "GLIDE_CROSS_KP", 22.0,
        "GLIDE_MAX_AOA", 16.0,
        "GLIDE_RCS_Q_CUTOFF", 0.09,
        "GLIDE_PRED_DT", 2.0,
        "GLIDE_PRED_STEPS", 240
    ).
}

CLEARSCREEN.
log_info("INIT", "==================================================").
log_info("INIT", "  Falcon 9 Booster Recovery v1.0 (Unified Core)  ").
log_info("INIT", "==================================================").

UNLOCK ALL.
SAS OFF.
SET rec_throttle TO 0.0.
SET rec_steering TO SHIP:UP:VECTOR.
LOCK THROTTLE TO rec_throttle.
LOCK STEERING TO rec_steering.

LOCAL cfg IS RECOVERY_CONFIG.
LOCAL recovery_mode IS cfg["RECOVERY_MODE"].
LOCAL mode_prof IS resolve_mode_profile(cfg, recovery_mode).

LOCAL guide IS cfg["GUIDANCE"]:COPY.
SET guide["COAST_ENTRY_ALT"] TO mode_prof["COAST_ENTRY_ALT"].
IF mode_prof:HASKEY("EB_END_SPEED") {
    SET guide["ENTRY_BURN_END_SPEED"] TO mode_prof["EB_END_SPEED"].
}
IF mode_prof:HASKEY("EB_MIN_LANDING_PROP_T") {
    SET guide["EB_MIN_LANDING_PROP_T"] TO mode_prof["EB_MIN_LANDING_PROP_T"].
}

LOCAL landing_cfg IS cfg["LANDING_ATTITUDE"].
LOCAL sm_cfg IS cfg["STEERING_MANAGER"].
LOCAL act_cfg IS cfg["ACTUATORS"].
LOCAL target_landing_geo IS resolve_landing_site(cfg["LANDING_SITE"]).
LOCAL deck_elev IS 0.0.
IF mode_prof:HASKEY("DECK_ELEVATION") { SET deck_elev TO mode_prof["DECK_ELEVATION"]. }
LOCAL eff_site_elev IS MAX(0.0, MAX(MAX(cfg["LANDING_SITE"]["ELEVATION"], deck_elev), target_landing_geo:TERRAINHEIGHT)).

LOCAL pred_cfg IS cfg["PREDICTOR"]:COPY.
SET pred_cfg["MIN_ALT"] TO MAX(pred_cfg["MIN_ALT"], eff_site_elev).

LOCAL aero_cfg IS cfg["AERO"]:COPY.
SET aero_cfg["RCS_Q_CUTOFF"] TO mode_prof["GLIDE_RCS_Q_CUTOFF"].
IF mode_prof:HASKEY("USE_AUTH_NORM")       { SET aero_cfg["USE_AUTH_NORM"] TO mode_prof["USE_AUTH_NORM"]. }
IF mode_prof:HASKEY("Q_SCALE_KPA")         { SET aero_cfg["Q_SCALE_KPA"]   TO mode_prof["Q_SCALE_KPA"]. }
IF mode_prof:HASKEY("AUTH_MIN_M")          { SET aero_cfg["AUTH_MIN_M"]    TO mode_prof["AUTH_MIN_M"]. }
IF mode_prof:HASKEY("AUTH_MAX_M")          { SET aero_cfg["AUTH_MAX_M"]    TO mode_prof["AUTH_MAX_M"]. }
IF mode_prof:HASKEY("GLIDE_DOWN_KP")       { SET aero_cfg["DOWN_KP"]       TO mode_prof["GLIDE_DOWN_KP"]. }
IF mode_prof:HASKEY("GLIDE_CROSS_KP")      { SET aero_cfg["CROSS_KP"]      TO mode_prof["GLIDE_CROSS_KP"]. }
IF mode_prof:HASKEY("GLIDE_MAX_AOA")       { SET aero_cfg["MAX_AOA_DEG"]   TO mode_prof["GLIDE_MAX_AOA"]. }
IF mode_prof:HASKEY("HANDOFF_OVERSHOOT_M") {
    SET aero_cfg["HANDOFF_OVERSHOOT_M"] TO mode_prof["HANDOFF_OVERSHOOT_M"].
} ELSE IF landing_cfg:HASKEY("HANDOFF_OVERSHOOT_M") {
    SET aero_cfg["HANDOFF_OVERSHOOT_M"] TO landing_cfg["HANDOFF_OVERSHOOT_M"].
}

LOCAL initial_state IS cfg["INITIAL_STATE"].
IF initial_state = "AUTO" {
    SET initial_state TO choose_recovery_initial_state(cfg).
}

LOCAL old_ipu IS CONFIG:IPU.
SET CONFIG:IPU TO MAX(200, cfg["SAFETY"]["KOS_IPU"]).

IF initial_state = "ST_AERO_GLIDE" {
    configure_steering_aero(sm_cfg).
} ELSE IF initial_state = "ST_LANDING_BURN" {
    configure_steering_landing().
} ELSE {
    configure_steering_manager(sm_cfg).
}
init_engine_manager(act_cfg["ENGINE_MODE_AT_START"]).
// Ensure booster RCS modules are armed (guards against rapid staging < 0.2 s after MECO)
FOR rcs_item IN SHIP:RCS {
    IF rcs_item:ISTYPE("RCS") AND rcs_item:HASSUFFIX("ENABLED") {
        IF NOT rcs_item:ENABLED {
            SET rcs_item:ENABLED TO TRUE.
        }
    }
}
IF recovery_mode = "RTLS" AND initial_state = "ST_FLIP" {
    SET STEERINGMANAGER:MAXSTOPPINGTIME TO 4.5.
    SET STEERINGMANAGER:PITCHTS TO 1.8.
    SET STEERINGMANAGER:YAWTS TO 1.8.
    SET STEERINGMANAGER:PITCHPID:KP TO 1.4.
    SET STEERINGMANAGER:YAWPID:KP TO 1.4.
}

LOCAL max_aoa IS MAX(0.1, MIN(aero_cfg["MAX_AOA_DEG"], 18.0)).
LOCAL aero_down_pid IS create_pid(aero_cfg["DOWN_KP"], aero_cfg["DOWN_KI"],
                                  aero_cfg["DOWN_KD"], -18.0, 18.0).
LOCAL aero_cross_pid IS create_pid(aero_cfg["CROSS_KP"], aero_cfg["CROSS_KI"],
                                   aero_cfg["CROSS_KD"], -18.0, 18.0).
LOCAL aero_state IS init_aero_guidance().
LOCAL bb_state IS init_boostback_state().
LOCAL pred_flight_time IS 150.0.
GLOBAL pred_lead_m IS 0.0.
LOCAL pred_glide_rad_m IS 2000.0.
LOCAL eb_dr_dv IS 22.0.
LOCAL eb_pred_v IS -1.0.
LOCAL eb_pred_over IS 0.0.

log_info("INIT", "Mode: " + recovery_mode + " | Entry Alt: " + ROUND(guide["COAST_ENTRY_ALT"]/1000.0, 1) +
                 " km | State: " + initial_state + " | Prop: " + ROUND(get_usable_main_prop_mass(), 2) + " t").

LOCAL fsm IS make_fsm(initial_state).
LOCAL rcs_ctrl_state IS init_rcs_controller_state().
LOCAL n2_prev_phase IS get_nitrogen_amount().
LOCAL n2_last_state IS fsm["current_state"].
LOCAL rcs_on_sec IS 0.0.
LOCAL start_time IS TIME:SECONDS.
LOCAL prev_time IS TIME:SECONDS.
LOCAL hud_time IS 0.0.
LOCAL pred_time IS 0.0.
LOCAL fin_tune_time IS 0.0.
LOCAL pred_geo IS SHIP:GEOPOSITION.
LOCAL pred_ok IS FALSE.
LOCAL pred_warned IS FALSE.
LOCAL fins_deployed IS (initial_state = "ST_AERO_GLIDE" OR initial_state = "ST_LANDING_BURN").
IF fins_deployed {
    set_gridfin_deflection(25.0, act_cfg["GRIDFIN_PART_KEYWORD"]).
}
LOCAL legs_deployed IS FALSE.
LOCAL entry_mode_set IS (initial_state = "ST_AERO_GLIDE" OR initial_state = "ST_LANDING_BURN").
LOCAL landing_mode_set IS (initial_state = "ST_LANDING_BURN").
LOCAL rtls_coast_braking IS FALSE.
LOCAL mission_active IS TRUE.

UNTIL NOT mission_active {
    LOCAL dt IS MAX(0.001, TIME:SECONDS - prev_time).
    SET prev_time TO TIME:SECONDS.

    LOCAL radar_alt IS get_corrected_radar_altitude(
        TUNDRA_F9_PROFILE["LANDING_GEAR_OFFSET"],
        eff_site_elev
    ).
    LOCAL usable_prop_t IS get_usable_main_prop_mass().
    LOCAL eff_dry_kg IS MAX(10000.0, (SHIP:MASS - usable_prop_t) * 1000.0).
    LOCAL vert_speed IS SHIP:VERTICALSPEED.
    LOCAL horiz_speed IS get_horizontal_speed(SHIP:VELOCITY:SURFACE).
    LOCAL state_elapsed IS TIME:SECONDS - fsm["state_time"].
    LOCAL dyn_q IS SHIP:Q.
    LOCAL retro_vec IS safe_normalize(-SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR).
    LOCAL vh_coast_dir IS safe_normalize(vxcl(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), SHIP:NORTH:VECTOR).
    LOCAL coast_pitch_deg IS mode_prof["COAST_PITCH_DEG"].
    LOCAL coast_att_vec IS (-vh_coast_dir * COS(coast_pitch_deg) + SHIP:UP:VECTOR * SIN(coast_pitch_deg)):NORMALIZED.
    LOCAL high_steer_vec IS retro_vec.

    LOCAL cur_st IS fsm["current_state"].
    LOCAL sim_eb_flag IS (cur_st = "ST_FLIP" OR cur_st = "ST_BOOSTBACK" OR cur_st = "ST_COAST").
    LOCAL eff_pred_period IS pred_cfg["UPDATE_PERIOD"].
    IF cur_st = "ST_BOOSTBACK" OR cur_st = "ST_ENTRY_BURN" {
        SET eff_pred_period TO 0.20.
    }

    IF cur_st <> "ST_LANDING_BURN" AND (TIME:SECONDS - pred_time > eff_pred_period) {
        LOCAL run_pred_cfg IS pred_cfg.
        IF cur_st = "ST_BOOSTBACK" OR cur_st = "ST_ENTRY_BURN" {
            SET run_pred_cfg TO pred_cfg:COPY.
            SET run_pred_cfg["DT"] TO 2.0.
            SET run_pred_cfg["MAX_STEPS"] TO 240.
        } ELSE IF cur_st = "ST_AERO_GLIDE" AND mode_prof["GLIDE_PRED_DT"] < pred_cfg["DT"] {
            SET run_pred_cfg TO pred_cfg:COPY.
            SET run_pred_cfg["DT"] TO mode_prof["GLIDE_PRED_DT"].
            SET run_pred_cfg["MAX_STEPS"] TO mode_prof["GLIDE_PRED_STEPS"].
        }

        LOCAL run_guide IS guide.
        IF sim_eb_flag AND recovery_mode = "RTLS" {
            SET run_guide TO guide:COPY.
            SET run_guide["ENTRY_BURN_END_SPEED"] TO MAX(guide["ENTRY_BURN_END_SPEED"], mode_prof["BB_AIM_EB_END_SPEED"]).
        }

        LOCAL pred_params IS make_prediction_params(run_pred_cfg, sim_eb_flag, run_guide, -1.0, TRUE, eff_dry_kg).
        LOCAL pred_result IS predict_impact_state(pred_params).
        SET pred_geo TO pred_result["GEO"].
        SET pred_ok TO pred_result["OK"].
        SET pred_flight_time TO pred_result["TIME"].
        IF pred_result:HASKEY("LEAD_M") {
            SET pred_lead_m TO pred_result["LEAD_M"].
        }
        IF pred_ok AND pred_result:HASKEY("GLIDE_RADIUS_M") {
            SET pred_glide_rad_m TO pred_result["GLIDE_RADIUS_M"].
        }
        SET bb_state["DV_SINCE_PRED"] TO V(0, 0, 0).
        IF cur_st = "ST_ENTRY_BURN" AND pred_ok {
            LOCAL v_srf_now IS SHIP:VELOCITY:SURFACE:MAG.
            LOCAL cur_over_raw IS -1.0 * ((target_landing_geo:POSITION - pred_geo:POSITION) * vh_coast_dir).
            IF eb_pred_v > 0.0 AND (eb_pred_v - v_srf_now) > 3.0 {
                LOCAL raw_drdv IS (eb_pred_over - cur_over_raw) / (eb_pred_v - v_srf_now).
                IF raw_drdv > 5.0 AND raw_drdv < 60.0 {
                    SET eb_dr_dv TO eb_dr_dv * 0.65 + clamp(raw_drdv, 8.0, 45.0) * 0.35.
                }
            }
            SET eb_pred_v TO v_srf_now.
            SET eb_pred_over TO cur_over_raw.
        }
        SET pred_time TO TIME:SECONDS.
        IF NOT pred_ok AND NOT pred_warned {
            log_warn("PRED", "Impact integration did not reach ground; check MAX_STEPS/DT.").
            SET pred_warned TO TRUE.
        }
    }

    IF fins_deployed AND TIME:SECONDS - fin_tune_time > 1.0 {
        LOCAL fin_pct IS tune_gridfin_authority(dyn_q).
        SET fin_tune_time TO TIME:SECONDS.
    }

    // ---- FSM Branches ----
    IF fsm["current_state"] = "ST_FLIP" {
        SET rec_throttle TO 0.0.

        IF recovery_mode <> "RTLS" {
            LOCAL flip_tgt IS coast_att_vec.
            IF SHIP:ALTITUDE < (guide["COAST_ENTRY_ALT"] + 14000.0) AND vert_speed < 0.0 { SET flip_tgt TO retro_vec. }
            SET high_steer_vec TO flip_tgt.
            SET rec_steering TO make_glide_attitude(flip_tgt).
            IF VANG(SHIP:FACING:VECTOR, flip_tgt) < 25.0 OR SHIP:ALTITUDE < guide["COAST_ENTRY_ALT"] + 5000.0 {
                log_info("RECOVERY", "ASDS mode: Flip done -> Entering coast & deploying grid fins.").
                transition_fsm(fsm, "ST_COAST").
            }
        } ELSE {
            IF NOT entry_mode_set AND state_elapsed > 0.2 {
                set_engine_mode_three().
                SET entry_mode_set TO TRUE.
            }

            LOCAL flip_bb_vec IS calculate_boostback_vector(target_landing_geo, pred_geo).
            SET high_steer_vec TO flip_bb_vec.
            SET rec_steering TO make_glide_attitude(flip_bb_vec).

            LOCAL flip_py_omega IS vxcl(SHIP:FACING:VECTOR, SHIP:ANGULARVEL):MAG * (180.0 / CONSTANT:PI).

            IF state_elapsed > 1.5 AND VANG(SHIP:FACING:VECTOR, flip_bb_vec) < 30.0 AND flip_py_omega < 18.0 {
                configure_steering_vacuum(sm_cfg).
                log_info("RECOVERY", "RTLS fast flip ready (err=" +
                         ROUND(VANG(SHIP:FACING:VECTOR, flip_bb_vec), 1) + " deg, pyRate=" +
                         ROUND(flip_py_omega, 1) + " deg/s). Early boostback ignition!").
                transition_fsm(fsm, "ST_BOOSTBACK").
            }
        }
    }
    ELSE IF fsm["current_state"] = "ST_BOOSTBACK" {
        IF recovery_mode = "RTLS" {
            LOCAL bb_cmd IS step_boostback_guidance(
                target_landing_geo, pred_geo, pred_flight_time, dt, bb_state
            ).
            SET high_steer_vec TO bb_cmd["STEER_VEC"].
            SET rec_steering TO make_glide_attitude(bb_cmd["STEER_VEC"]).
            SET rec_throttle TO bb_cmd["THROTTLE"].

            LOCAL min_bb_prop IS 7.6.
            IF mode_prof:HASKEY("EB_MIN_LANDING_PROP_T") {
                SET min_bb_prop TO mode_prof["EB_MIN_LANDING_PROP_T"] + 3.0.
            }
            LOCAL bb_fuel_floor IS (usable_prop_t <= min_bb_prop).

            IF bb_cmd["CUTOFF"] OR bb_fuel_floor OR state_elapsed > 90.0 {
                SET rec_throttle TO 0.0.
                SET STEERINGMANAGER:MAXSTOPPINGTIME TO 2.5.
                SET rtls_coast_braking TO FALSE.
                IF bb_fuel_floor {
                    log_warn("RECOVERY", "Boostback cut off by propellant reserve guard (" + ROUND(usable_prop_t, 2) + " t left)!").
                }
                log_info("RECOVERY", "RTLS boostback complete. Cross err: " +
                         ROUND(bb_cmd["CROSS_ERR"], 0) + " m.").
                transition_fsm(fsm, "ST_COAST").
            }
        } ELSE {
            SET rec_throttle TO 0.0.
            log_info("RECOVERY", "ASDS mode skipping boostback. Entering coast.").
            transition_fsm(fsm, "ST_COAST").
        }
    }
    ELSE IF fsm["current_state"] = "ST_COAST" {
        SET rec_throttle TO 0.0.
        LOCAL coast_tgt IS coast_att_vec.
        IF SHIP:ALTITUDE < (guide["COAST_ENTRY_ALT"] + 14000.0) AND vert_speed < 0.0 {
            SET coast_tgt TO retro_vec.
        }
        SET high_steer_vec TO coast_tgt.
        SET rec_steering TO make_glide_attitude(coast_tgt).

        IF recovery_mode = "RTLS" AND (NOT rtls_coast_braking) AND VANG(SHIP:FACING:VECTOR, coast_tgt) < 28.0 {
            SET STEERINGMANAGER:MAXSTOPPINGTIME TO 1.2.
            SET rtls_coast_braking TO TRUE.
        }

        IF NOT fins_deployed {
            deploy_grid_fins(act_cfg["GRIDFIN_PART_KEYWORD"], act_cfg["GRIDFIN_EVENT_KEYWORD"]).
            SET fins_deployed TO TRUE.
            log_info("PRED", "Natural Impact Lat: " + ROUND(pred_geo:LAT, 4) + " | Lng: " + ROUND(pred_geo:LNG, 4)).
        }
        IF NOT entry_mode_set AND state_elapsed > 0.5 {
            set_engine_mode_three().
            SET entry_mode_set TO TRUE.
        }
        IF SHIP:ALTITUDE < guide["COAST_ENTRY_ALT"] AND state_elapsed > 1.0 {
            IF recovery_mode = "RTLS" { SET STEERINGMANAGER:MAXSTOPPINGTIME TO 1.2. }
            SET eb_pred_v TO -1.0.
            log_info("RECOVERY", "Entering atmospheric interface. Preparing entry burn.").
            transition_fsm(fsm, "ST_ENTRY_BURN").
        }
    }
    ELSE IF fsm["current_state"] = "ST_ENTRY_BURN" {
        IF NOT entry_mode_set {
            set_engine_mode_three().
            SET entry_mode_set TO TRUE.
        }

        LOCAL horiz_vel_dir IS safe_normalize(vxcl(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE), SHIP:NORTH:VECTOR).
        LOCAL cross_vel_dir IS safe_normalize(VCRS(SHIP:UP:VECTOR, horiz_vel_dir), SHIP:NORTH:VECTOR).
        LOCAL miss_vec IS target_landing_geo:POSITION - pred_geo:POSITION.
        LOCAL downrange_overshoot IS -1.0 * (miss_vec * horiz_vel_dir).
        LOCAL crossrange_err IS miss_vec * cross_vel_dir.

        LOCAL eb_steer IS retro_vec.
        IF pred_ok AND ABS(crossrange_err) > 50.0 AND
           (SHIP:VELOCITY:SURFACE:MAG < 1550.0 OR downrange_overshoot < 15000.0) {
            LOCAL cross_corr_deg IS clamp(crossrange_err * 0.003, -5.0, 5.0).
            LOCAL cross_steer_axis IS safe_normalize(vxcl(retro_vec, cross_vel_dir), SHIP:NORTH:VECTOR).
            SET eb_steer TO (eb_steer + cross_steer_axis * TAN(cross_corr_deg)):NORMALIZED.
        }

        IF recovery_mode = "RTLS" AND pred_ok AND downrange_overshoot > 350.0 AND dyn_q < 0.035 {
            LOCAL pitch_brake_deg IS clamp((downrange_overshoot - 350.0) * 0.006, 0.0, 12.0).
            LOCAL brake_pitch_axis IS safe_normalize(vxcl(retro_vec, -horiz_vel_dir), -SHIP:UP:VECTOR).
            SET eb_steer TO (eb_steer + brake_pitch_axis * TAN(pitch_brake_deg)):NORMALIZED.
        }

        SET high_steer_vec TO eb_steer.
        SET rec_steering TO make_glide_attitude(eb_steer, horiz_vel_dir).

        // Dead-reckoned live overshoot + live TWR * dR/dv analytic tail-off lead
        LOCAL v_srf_mag IS SHIP:VELOCITY:SURFACE:MAG.
        LOCAL live_over IS downrange_overshoot.
        IF pred_ok AND eb_pred_v > 0.0 {
            SET live_over TO downrange_overshoot - eb_dr_dv * MAX(0.0, eb_pred_v - v_srf_mag).
        }

        LOCAL eb_tail_tau IS 0.35.
        IF mode_prof:HASKEY("EB_TAILOFF_TAU_S") {
            SET eb_tail_tau TO mode_prof["EB_TAILOFF_TAU_S"].
        }
        LOCAL a_live IS SHIP:THRUST / MAX(SHIP:MASS, 1.0).
        LOCAL eb_lead IS eb_dr_dv * a_live * eb_tail_tau.
        LOCAL eb_max_safe_spd IS mode_prof["EB_MAX_SAFE_SPEED"].

        LOCAL eff_end_alt IS guide["ENTRY_BURN_END_ALT"].
        LOCAL eff_end_spd IS guide["ENTRY_BURN_END_SPEED"].
        LOCAL hs_lead IS compute_hoverslam_range_lead().
        LOCAL min_land_prop IS 4.6.
        IF mode_prof:HASKEY("EB_MIN_LANDING_PROP_T") { SET min_land_prop TO mode_prof["EB_MIN_LANDING_PROP_T"]. }
        LOCAL handoff_bias IS 15.0.
        IF aero_cfg:HASKEY("HANDOFF_OVERSHOOT_M") { SET handoff_bias TO aero_cfg["HANDOFF_OVERSHOOT_M"]. }

        // Decoupled terminal throttle ramp-down down to RealFuels 36.1% idle (cmd=0.01)
        LOCAL eb_throt IS guide["ENTRY_BURN_THROTTLE"].
        IF pred_ok AND state_elapsed > 1.5 AND live_over < 2600.0 AND
           (v_srf_mag < eb_max_safe_spd OR (v_srf_mag < eb_max_safe_spd + 160.0 AND SHIP:ALTITUDE > eff_end_alt + 4000.0)) {
            SET eb_throt TO clamp(0.01 + ((live_over - eb_lead) / MAX(2600.0 - eb_lead, 500.0)) * (eb_throt - 0.01), 0.01, eb_throt).
        }
        SET rec_throttle TO eb_throt.

        IF recovery_mode = "RTLS" AND pred_ok AND
           live_over > (hs_lead + 250.0) AND
           usable_prop_t > (min_land_prop + 2.0) {
            SET eff_end_alt TO MIN(eff_end_alt, 30000.0).
            SET eff_end_spd TO MIN(eff_end_spd, 520.0).
        }

        LOCAL fuel_floor_reached IS (usable_prop_t <= min_land_prop).
        LOCAL hard_limit_reached IS (
            SHIP:ALTITUDE < eff_end_alt OR
            v_srf_mag < eff_end_spd OR
            fuel_floor_reached
        ).
        LOCAL target_reached_safely IS (
            v_srf_mag < eb_max_safe_spd AND
            pred_ok AND
            live_over <= (hs_lead + eb_lead + handoff_bias)
        ).

        IF state_elapsed > 2.0 AND (hard_limit_reached OR target_reached_safely) {
            SET rec_throttle TO 0.0.
            SET aero_state["STEER"] TO retro_vec.
            SET aero_state["REF_HORIZ"] TO horiz_vel_dir.
            configure_steering_aero(sm_cfg).
            LOCAL post_eb_dist IS (target_landing_geo:POSITION - pred_geo:POSITION):MAG.
            IF fuel_floor_reached {
                log_warn("RECOVERY", "Entry burn cut off by landing propellant reserve guard (" + ROUND(usable_prop_t, 2) + " t left)!").
            }
            log_info("RECOVERY", "Entry burn complete (V=" + ROUND(SHIP:VELOCITY:SURFACE:MAG, 0) +
                                 " m/s, Alt=" + ROUND(SHIP:ALTITUDE / 1000.0, 1) + " km, Prop=" +
                                 ROUND(usable_prop_t, 2) + " t).").
            log_info("PRED", "Post-EntryBurn Impact Lat: " + ROUND(pred_geo:LAT, 4) +
                             " | Lng: " + ROUND(pred_geo:LNG, 4) +
                             " | Over: " + ROUND(downrange_overshoot, 0) + " m | Miss: " + ROUND(post_eb_dist, 0) + " m").
            transition_fsm(fsm, "ST_AERO_GLIDE").
        }
    }
    ELSE IF fsm["current_state"] = "ST_AERO_GLIDE" {
        SET rec_throttle TO 0.0.
        IF NOT landing_mode_set AND state_elapsed > 1.0 {
            set_engine_mode_single().
            SET landing_mode_set TO TRUE.
            log_info("RECOVERY", "Center engine mode pre-selected safely.").
        }
        SET rec_steering TO calculate_glide_steering(
            target_landing_geo, pred_geo, aero_cfg,
            aero_down_pid, aero_cross_pid, aero_state, dt, pred_glide_rad_m
        ).

        LOCAL avail_accel IS TUNDRA_F9_PROFILE["ENGINES"]["CENTER"]["MAX_THRUST_ASL"] / MAX(SHIP:MASS, 0.001).
        IF calculate_hoverslam_trigger(radar_alt, vert_speed, avail_accel,
                                       guide["HOVERSLAM_MARGIN"], horiz_speed) {
            IF NOT landing_mode_set {
                set_engine_mode_single().
                SET landing_mode_set TO TRUE.
            }
            configure_steering_landing().
            log_info("RECOVERY", "Hoverslam trigger. Center engine ignition!").
            transition_fsm(fsm, "ST_LANDING_BURN").
        }
    }
    ELSE IF fsm["current_state"] = "ST_LANDING_BURN" {
        SET rec_steering TO calculate_landing_steering(landing_cfg, target_landing_geo, radar_alt, aero_state["REF_HORIZ"]).
        SET aero_state["STEER"] TO rec_steering:VECTOR.
        LOCAL tilt_cos IS MAX(0.5, SHIP:FACING:VECTOR * SHIP:UP:VECTOR).
        SET rec_throttle TO solve_hoverslam_throttle(
            radar_alt,
            vert_speed,
            TUNDRA_F9_PROFILE["TOUCHDOWN_VELOCITY"],
            TUNDRA_F9_PROFILE["ENGINES"]["CENTER"]["MIN_THROTTLE"],
            guide["LANDING_THROTTLE_MAX"],
            tilt_cos
        ).

        IF radar_alt < guide["LEGS_DEPLOY_ALT"] AND NOT legs_deployed {
            deploy_landing_legs(act_cfg["LEG_PART_KEYWORD"], act_cfg["LEG_EVENT_KEYWORD"]).
            SET legs_deployed TO TRUE.
        }

        IF radar_alt <= guide["TOUCHDOWN_ALT"] OR (radar_alt <= 10.0 AND vert_speed >= -0.5) OR
           SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
            SET rec_throttle TO 0.0.
            LOCAL td_tilt IS VANG(SHIP:FACING:VECTOR, SHIP:UP:VECTOR).
            LOCAL td_miss IS vxcl(SHIP:UP:VECTOR, target_landing_geo:POSITION):MAG.
            log_info("TOUCHDOWN", "Touchdown params: Vspd=" + ROUND(vert_speed, 2) +
                                  " m/s | Hspd=" + ROUND(horiz_speed, 2) +
                                  " m/s | Tilt=" + ROUND(td_tilt, 2) +
                                  " deg | Miss=" + ROUND(td_miss, 1) + " m").
            transition_fsm(fsm, "ST_TOUCHDOWN").
        }
    }
    ELSE IF fsm["current_state"] = "ST_TOUCHDOWN" {
        SET rec_throttle TO 0.0.
        log_info("TOUCHDOWN", "Touchdown confirmed! Booster recovered successfully.").
        SET mission_active TO FALSE.
    }

    LOCAL rcs_active IS manage_rcs_high_alt(
        fsm["current_state"],
        aero_cfg["RCS_Q_CUTOFF"],
        high_steer_vec,
        aero_state["STEER"],
        rcs_ctrl_state,
        recovery_mode,
        guide["COAST_ENTRY_ALT"]
    ).
    IF rcs_active { SET rcs_on_sec TO rcs_on_sec + dt. }

    IF fsm["current_state"] <> n2_last_state {
        LOCAL n2_now IS get_nitrogen_amount().
        LOCAL n2_used IS MAX(0.0, n2_prev_phase - n2_now).
        log_info("RCS", n2_last_state + " used " + ROUND(n2_used / 1000.0, 1) +
                        " kL (ON " + ROUND(rcs_on_sec, 1) + "s) | N2 left: " +
                        ROUND(n2_now / 1000.0, 1) + " kL").
        SET n2_prev_phase TO n2_now.
        SET n2_last_state TO fsm["current_state"].
        SET rcs_on_sec TO 0.0.
    }

    IF TIME:SECONDS - start_time > cfg["SAFETY"]["MAX_FLIGHT_TIME"] {
        log_warn("RECOVERY", "Recovery time guard exceeded. Releasing controls.").
        SET mission_active TO FALSE.
    }

    IF TIME:SECONDS - hud_time > 0.2 {
        SET hud_time TO TIME:SECONDS.
        LOCAL hud_tgo IS pred_flight_time.
        IF fsm["current_state"] = "ST_LANDING_BURN" {
            SET hud_tgo TO MAX(0.0, (2.0 * radar_alt) / MAX(ABS(vert_speed) + 1.2, 1.0)).
        }
        render_hud(fsm["current_state"], radar_alt, vert_speed, horiz_speed,
                   rec_throttle, recovery_mode, usable_prop_t, hud_tgo).
    }
    WAIT 0.02.
}

UNLOCK THROTTLE.
UNLOCK STEERING.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
set_rcs_state(FALSE).
restore_steering_manager().
IF cfg["SAFETY"]["RESTORE_IPU"] {
    SET CONFIG:IPU TO old_ipu.
}
log_info("RECOVERY", "Recovery guidance terminated. All flight locks released.").