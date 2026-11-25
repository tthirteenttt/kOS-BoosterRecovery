// ============================================================================
// [2/3] Ascent & UPEG Guidance Entry (ascent.ks) v1.0 —— Release
// Usage: SWITCH TO 0. RUN ascent.
// ============================================================================

RUNONCEPATH("0:/vessels/tundra_f9_profile.ks").
RUNONCEPATH("0:/lib/core/math.ks").
RUNONCEPATH("0:/lib/core/fsm.ks").
RUNONCEPATH("0:/lib/core/logger.ks").
RUNONCEPATH("0:/lib/physics/aero_atmo.ks").
RUNONCEPATH("0:/lib/nav/state_estimator.ks").
RUNONCEPATH("0:/lib/guidance/upeg_guide.ks").
RUNONCEPATH("0:/lib/guidance/lan_window.ks").
RUNONCEPATH("0:/lib/guidance/staging_predictor.ks").
RUNONCEPATH("0:/lib/guidance/predictor_rk4.ks").
RUNONCEPATH("0:/lib/guidance/asds_calculator.ks").
RUNONCEPATH("0:/lib/telemetry/hud_display.ks").
RUNONCEPATH("0:/lib/control/engine_manager.ks").
RUNPATH("0:/config/ascent_config.ks").

// Singularity-free 3D ascent attitude from 90 deg vertical to 0 deg horizontal
FUNCTION make_ascent_attitude {
    PARAMETER az_deg, pitch_deg.

    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL az_vec IS HEADING(az_deg, 0.0):VECTOR.
    LOCAL p_clamped IS clamp(pitch_deg, 0.0, 90.0).

    LOCAL fore_vec IS (az_vec * COS(p_clamped) + up_vec * SIN(p_clamped)):NORMALIZED.
    LOCAL top_vec IS (-az_vec * SIN(p_clamped) + up_vec * COS(p_clamped)):NORMALIZED.
    RETURN LOOKDIRUP(fore_vec, top_vec).
}

// Stage 1 ascent SteeringManager: pure roll-rate damping + high roll torque factor to eliminate 9-engine roll chatter
FUNCTION configure_s1_ascent_steering {
    STEERINGMANAGER:RESETPIDS().
    SET STEERINGMANAGER:MAXSTOPPINGTIME TO 1.5.
    SET STEERINGMANAGER:PITCHTS TO 2.0.
    SET STEERINGMANAGER:YAWTS TO 2.0.
    SET STEERINGMANAGER:ROLLTS TO 8.0.

    SET STEERINGMANAGER:PITCHPID:KP TO 1.2.
    SET STEERINGMANAGER:YAWPID:KP TO 1.2.
    SET STEERINGMANAGER:PITCHPID:KI TO 0.25.
    SET STEERINGMANAGER:YAWPID:KI TO 0.25.
    SET STEERINGMANAGER:PITCHPID:KD TO 0.2.
    SET STEERINGMANAGER:YAWPID:KD TO 0.2.

    SET STEERINGMANAGER:ROLLPID:KP TO 0.10.
    SET STEERINGMANAGER:ROLLPID:KI TO 0.0.
    SET STEERINGMANAGER:ROLLPID:KD TO 0.0.
    SET STEERINGMANAGER:ROLLTORQUEFACTOR TO 15.0.
    SET STEERINGMANAGER:TORQUEEPSILONMIN TO 0.012.
    SET STEERINGMANAGER:TORQUEEPSILONMAX TO 0.035.
    SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO -1.0.
}

FUNCTION configure_s2_upeg_steering {
    STEERINGMANAGER:RESETPIDS().
    SET STEERINGMANAGER:MAXSTOPPINGTIME TO 1.0.
    SET STEERINGMANAGER:PITCHTS TO 2.2.
    SET STEERINGMANAGER:YAWTS TO 2.2.
    SET STEERINGMANAGER:ROLLTS TO 6.0.

    SET STEERINGMANAGER:PITCHPID:KP TO 1.0.
    SET STEERINGMANAGER:YAWPID:KP TO 1.0.
    SET STEERINGMANAGER:PITCHPID:KI TO 0.0.
    SET STEERINGMANAGER:YAWPID:KI TO 0.0.
    SET STEERINGMANAGER:PITCHPID:KD TO 0.25.
    SET STEERINGMANAGER:YAWPID:KD TO 0.25.

    SET STEERINGMANAGER:ROLLPID:KP TO 0.15.
    SET STEERINGMANAGER:ROLLPID:KI TO 0.0.
    SET STEERINGMANAGER:ROLLPID:KD TO 0.0.
    SET STEERINGMANAGER:ROLLTORQUEFACTOR TO 5.0.
    SET STEERINGMANAGER:TORQUEEPSILONMIN TO 0.008.
    SET STEERINGMANAGER:TORQUEEPSILONMAX TO 0.025.
    SET STEERINGMANAGER:ROLLCONTROLANGLERANGE TO -1.0.
}

CLEARSCREEN.
log_info("INIT", "==================================================").
log_info("INIT", "  Falcon 9 Ascent & UPEG Guidance v0.8            ").
log_info("INIT", "==================================================").

UNLOCK ALL.
SAS OFF.
RCS OFF.

LOCAL cfg IS ASCENT_CONFIG.
LOCAL profile IS cfg["ASCENT_PROFILE"].
LOCAL staging IS cfg["STAGING"].
LOCAL tgt_orbit IS cfg["TARGET_ORBIT"].
LOCAL veh_info IS inspect_vehicle_mass_breakdown().
LOCAL s1_prop IS veh_info["S1_PROP_MASS"].
LOCAL reserve IS get_required_reserve_propellant(cfg["RECOVERY_MODE"]).
LOCAL meco_mass IS cfg["MECO_MASS"].
LOCAL init_tower_mass IS veh_info["TOWER_MASS"].
LOCAL pad_mass IS veh_info["PAD_PURE_MASS"].
LOCAL s1_burned_prop IS 0.0.

IF init_tower_mass > 10.0 {
    log_info("INIT", "Launch tower detected (" + ROUND(init_tower_mass, 1) + " t); excluded from pad mass.").
    IF meco_mass > pad_mass {
        SET meco_mass TO meco_mass - init_tower_mass.
        log_warn("INIT", "MECO_MASS included tower weight; auto-adjusted to " + ROUND(meco_mass, 2) + " t.").
    }
}

LOCAL is_fixed_lan IS (tgt_orbit:HASKEY("LAN_MODE") AND tgt_orbit["LAN_MODE"] = "FIXED").
LOCAL tgt_lan IS 0.0.
IF tgt_orbit:HASKEY("LAN") { SET tgt_lan TO tgt_orbit["LAN"]. }
LOCAL lan_lead IS 150.0.
IF tgt_orbit:HASKEY("LAN_LEAD_TIME") { SET lan_lead TO tgt_orbit["LAN_LEAD_TIME"]. }
LOCAL auto_warp IS TRUE.
IF tgt_orbit:HASKEY("AUTO_WARP") { SET auto_warp TO tgt_orbit["AUTO_WARP"]. }

LOCAL go_south IS resolve_launch_south_branch(
    SHIP:GEOPOSITION,
    tgt_orbit["INCLINATION"],
    profile["LAUNCH_SOUTH"],
    tgt_lan,
    lan_lead,
    is_fixed_lan
).

IF is_fixed_lan AND SHIP:ALTITUDE < 1000.0 AND SHIP:VELOCITY:SURFACE:MAG < 5.0 {
    wait_for_lan_window(tgt_orbit["INCLINATION"], tgt_lan, go_south, lan_lead, auto_warp).
    CLEARSCREEN.
}

LOCAL start_time IS TIME:SECONDS.

LOCAL launch_azimuth IS profile["MANUAL_AZIMUTH"].
IF profile["USE_TARGET_AZIMUTH"] {
    SET launch_azimuth TO solve_launch_azimuth_3d(
        SHIP:GEOPOSITION,
        tgt_orbit["INCLINATION"],
        tgt_orbit["PERIAPSIS"],
        go_south
    ).
}

LOCAL old_ipu IS CONFIG:IPU.
SET CONFIG:IPU TO 2000.

SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.0.
configure_s1_ascent_steering().
SET ascent_throttle TO 0.0.
SET ascent_steering TO make_ascent_attitude(launch_azimuth, 90.0).
LOCK THROTTLE TO ascent_throttle.
LOCK STEERING TO ascent_steering.

LOCAL upeg_state IS init_upeg(tgt_orbit, cfg["UPEG"]["MAX_BURN_TIME"]).
log_info("INIT", "MECO_MASS = " + ROUND(meco_mass, 2) + " t | Pad mass = " + ROUND(pad_mass, 2) + " t | Azimuth = " + ROUND(launch_azimuth, 2) + " deg").

LOCAL fsm IS make_fsm("ST_PRELAUNCH").
LOCAL prev_mass IS SHIP:MASS.
LOCAL prev_time IS TIME:SECONDS.
LOCAL hud_time IS 0.0.
LOCAL meco_time IS 0.0.
LOCAL stage_at_meco IS SHIP:STAGENUM.
LOCAL mass_at_meco IS SHIP:MASS.
LOCAL meco_hold_attitude IS ascent_steering.
LOCAL s2_sep_time IS 0.0.
LOCAL s2_ignited IS FALSE.
LOCAL cmd_pitch_smooth IS 90.0.
LOCAL fairing_reminded IS FALSE.
LOCAL wait_notice_printed IS FALSE.
LOCAL mission_active IS TRUE.

UNTIL NOT mission_active {
    // Hard interlock: keep RCS strictly OFF until Stage 1 / Stage 2 physical separation
    IF fsm["current_state"] = "ST_PRELAUNCH" OR
       fsm["current_state"] = "ST_ASCENT_VERTICAL" OR
       fsm["current_state"] = "ST_ASCENT_GRAVITY_TURN" OR
       fsm["current_state"] = "ST_WAIT_STAGING" {
        IF RCS { RCS OFF. }
    }

    LOCAL dt IS MAX(0.001, TIME:SECONDS - prev_time).
    SET prev_time TO TIME:SECONDS.
    LOCAL frame_dm IS prev_mass - SHIP:MASS.
    SET prev_mass TO SHIP:MASS.
    LOCAL m_dot IS 0.0.

    IF frame_dm >= 10.0 AND SHIP:ALTITUDE < cfg["MIN_MECO_ALT"] {
        SET pad_mass TO SHIP:MASS + s1_burned_prop.
        IF meco_mass > pad_mass {
            SET meco_mass TO meco_mass - frame_dm.
        }
        log_info("ASCENT", "Clamp release (-" + ROUND(frame_dm, 1) + " t) | Pad mass: " +
                           ROUND(pad_mass, 2) + " t | MECO target: " + ROUND(meco_mass, 2) + " t").
    } ELSE IF frame_dm > 0.0 AND frame_dm < 5.0 {
        SET m_dot TO frame_dm / dt.
        IF fsm["current_state"] = "ST_ASCENT_VERTICAL" OR fsm["current_state"] = "ST_ASCENT_GRAVITY_TURN" {
            SET s1_burned_prop TO s1_burned_prop + frame_dm.
        }
    }

    LOCAL radar_alt IS get_corrected_radar_altitude(TUNDRA_F9_PROFILE["LANDING_GEAR_OFFSET"]).
    LOCAL vert_speed IS SHIP:VERTICALSPEED.
    LOCAL horiz_speed IS get_horizontal_speed(SHIP:VELOCITY:SURFACE).
    LOCAL s1_fuel IS MAX(0.0, s1_prop - s1_burned_prop).
    LOCAL t_go_meco IS predict_mass_meco_time(SHIP:MASS, meco_mass, m_dot).

    // 1. Prelaunch & vertical liftoff
    IF fsm["current_state"] = "ST_PRELAUNCH" {
        SET ascent_throttle TO 0.0.
        SET ascent_steering TO make_ascent_attitude(launch_azimuth, 90.0).
        set_engine_mode_all().

        IF profile["AUTO_IGNITE"] {
            SET ascent_throttle TO 1.0.
            WAIT 0.1.
            STAGE.
            WAIT profile["IGNITION_WAIT"].
            log_info("ASCENT", "First stage ignition. Lift-off!").
            transition_fsm(fsm, "ST_ASCENT_VERTICAL").
        } ELSE {
            IF SHIP:AVAILABLETHRUST > 1000.0 {
                SET ascent_throttle TO 1.0.
                log_info("ASCENT", "Manual ignition detected. Taking over ascent.").
                transition_fsm(fsm, "ST_ASCENT_VERTICAL").
            }
        }
    }
    ELSE IF fsm["current_state"] = "ST_ASCENT_VERTICAL" {
        SET ascent_throttle TO 1.0.
        SET ascent_steering TO make_ascent_attitude(launch_azimuth, 90.0).

        IF radar_alt >= profile["PITCH_START_ALT"] AND vert_speed > 45.0 {
            log_info("ASCENT", "Pitchover start at radar alt " + ROUND(radar_alt, 0) + " m.").
            transition_fsm(fsm, "ST_ASCENT_GRAVITY_TURN").
        }
    }
    // 2. Gravity turn & pre-MECO TVC rate arrest
    ELSE IF fsm["current_state"] = "ST_ASCENT_GRAVITY_TURN" {
        IF SHIP:ALTITUDE > cfg["MIN_MECO_ALT"] AND SHIP:MASS <= (meco_mass + 10.0) {
            IF SHIP:MASS <= (meco_mass + 2.5) {
                SET ascent_throttle TO 0.20.
            } ELSE {
                SET ascent_throttle TO 0.65.
            }
            SET ascent_steering TO make_ascent_attitude(launch_azimuth, cmd_pitch_smooth).
        } ELSE {
            SET ascent_throttle TO 1.0.

            LOCAL h_frac IS (SHIP:ALTITUDE - profile["PITCH_START_ALT"]) /
                            MAX(1.0, profile["PITCH_END_ALT"] - profile["PITCH_START_ALT"]).
            SET h_frac TO clamp(h_frac, 0.0, 1.0).
            LOCAL pitch_span IS 90.0 - profile["TARGET_PITCH_END"].
            LOCAL nom_pitch IS 90.0 - pitch_span * (h_frac ^ profile["PITCH_CURVE_EXP"]).

            LOCAL q_kpa IS SHIP:Q * CONSTANT:ATMtokPa.
            IF q_kpa > 2.5 AND SHIP:VELOCITY:SURFACE:MAG > 100.0 {
                LOCAL srf_prograde_pitch IS 90.0 - VANG(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE).
                LOCAL max_aoa IS 5.0.
                IF profile:HASKEY("MAX_AOA_DEG") { SET max_aoa TO profile["MAX_AOA_DEG"]. }
                LOCAL dyn_aoa_lim IS clamp(max_aoa * (25.0 / MAX(q_kpa, 15.0)), 3.5, 8.0).
                SET nom_pitch TO clamp(nom_pitch, srf_prograde_pitch - dyn_aoa_lim, srf_prograde_pitch + dyn_aoa_lim).
            }

            LOCAL pitch_alpha IS clamp(1.0 - (CONSTANT:E ^ (-dt / 0.20)), 0.02, 1.0).
            SET cmd_pitch_smooth TO cmd_pitch_smooth * (1.0 - pitch_alpha) + nom_pitch * pitch_alpha.
            SET ascent_steering TO make_ascent_attitude(launch_azimuth, cmd_pitch_smooth).
        }

        LOCAL mass_hit IS check_meco_by_mass(SHIP:MASS, meco_mass, SHIP:ALTITUDE, cfg["MIN_MECO_ALT"]).
        LOCAL reserve_hit IS FALSE.
        IF cfg["FALLBACK_RESERVE_ON"] {
            SET reserve_hit TO check_meco_by_reserve(SHIP:MASS, pad_mass, s1_prop, reserve,
                                                    SHIP:ALTITUDE, cfg["MIN_MECO_ALT"]).
        }

        IF mass_hit OR reserve_hit {
            SET ascent_throttle TO 0.0.
            SET meco_hold_attitude TO make_ascent_attitude(launch_azimuth, cmd_pitch_smooth).
            SET ascent_steering TO meco_hold_attitude.
            SET mass_at_meco TO SHIP:MASS.
            SET stage_at_meco TO SHIP:STAGENUM.
            SET meco_time TO TIME:SECONDS.
            IF reserve_hit {
                log_warn("ASCENT", "MECO triggered by propellant reserve fallback!").
            } ELSE {
                log_info("ASCENT", "MECO reached at " + ROUND(SHIP:MASS, 2) + " t / " + ROUND(SHIP:ALTITUDE, 0) + " m.").
            }
            transition_fsm(fsm, "ST_WAIT_STAGING").
        }
    }
    // 3. Wait for staging
    ELSE IF fsm["current_state"] = "ST_WAIT_STAGING" {
        SET ascent_throttle TO 0.0.
        SET ascent_steering TO meco_hold_attitude.

        IF NOT wait_notice_printed {
            log_info("ASCENT", "MECO attitude locked. Wait 1s for thrust tail-off then press SPACE to stage.").
            SET wait_notice_printed TO TRUE.
        }

        LOCAL staged IS (SHIP:STAGENUM < stage_at_meco) OR
                        (SHIP:MASS < mass_at_meco - staging["STAGE_MASS_DROP"]).
        IF staged {
            IF SHIP:MASS >= staging["UPPER_STAGE_MIN_MASS"] {
                SET meco_hold_attitude TO LOOKDIRUP(SHIP:FACING:VECTOR, SHIP:FACING:TOPVECTOR).
                SET ascent_steering TO meco_hold_attitude.
                RCS ON.
                SET SHIP:CONTROL:FORE TO 1.0.
                SET s2_sep_time TO TIME:SECONDS.
                SET s2_ignited TO FALSE.
                configure_s2_upeg_steering().
                log_info("ASCENT", "S2 separation detected. Ullage active, clearing interstage...").
                transition_fsm(fsm, "ST_S2_CLEARANCE").
            } ELSE {
                log_info("ASCENT", "CPU remains on booster; ascent script exiting cleanly.").
                SET mission_active TO FALSE.
            }
        } ELSE IF TIME:SECONDS - meco_time > staging["STAGING_TIMEOUT"] {
            log_warn("ASCENT", "Staging timeout. Releasing controls.").
            SET mission_active TO FALSE.
        }
    }
    // 4. S2 MVac nozzle interstage clearance
    ELSE IF fsm["current_state"] = "ST_S2_CLEARANCE" {
        SET ascent_steering TO meco_hold_attitude.
        LOCAL clear_elapsed IS TIME:SECONDS - s2_sep_time.
        LOCAL clear_wait IS 2.0.
        IF staging:HASKEY("S2_CLEARANCE_WAIT") { SET clear_wait TO staging["S2_CLEARANCE_WAIT"]. }

        IF clear_elapsed < clear_wait {
            SET SHIP:CONTROL:FORE TO 1.0.
            IF SHIP:AVAILABLETHRUST > 10.0 {
                SET ascent_throttle TO 1.0.
                SET s2_ignited TO TRUE.
            } ELSE {
                SET ascent_throttle TO 0.0.
            }
        } ELSE {
            IF NOT s2_ignited {
                IF staging["S2_IGNITION_STAGE"] AND SHIP:AVAILABLETHRUST < 1.0 {
                    STAGE.
                    log_info("ASCENT", "Interstage cleared. S2 MVac ignition commanded!").
                }
                SET s2_ignited TO TRUE.
            }
            SET ascent_throttle TO 1.0.

            IF clear_elapsed >= clear_wait + staging["S2_IGNITION_WAIT"] {
                SET SHIP:CONTROL:FORE TO 0.0.
                SET upeg_state TO init_upeg(tgt_orbit, cfg["UPEG"]["MAX_BURN_TIME"]).
                log_info("ASCENT", "MVac thrust stable. Handing over to UPEG closed-loop guidance.").
                transition_fsm(fsm, "ST_S2_UPEG").
            }
        }
    }
    // 5. S2 UPEG closed-loop orbital insertion
    ELSE IF fsm["current_state"] = "ST_S2_UPEG" {
        LOCAL s2_tgo IS upeg_state["t_go"].
        SET ascent_throttle TO clamp((s2_tgo - 1.0) / 3.5, 0.01, 1.0).
        SET ascent_steering TO step_upeg_guidance(upeg_state, dt).

        IF staging["FAIRING_REMINDER_ALT"] > 0.0 AND
           SHIP:ALTITUDE > staging["FAIRING_REMINDER_ALT"] AND
           NOT fairing_reminded {
            log_info("ASCENT", "Passed " + ROUND(staging["FAIRING_REMINDER_ALT"] / 1000.0, 0) + " km fairing altitude; deploy fairings manually.").
            SET fairing_reminded TO TRUE.
        }

        IF upeg_state["cutoff"] {
            SET ascent_throttle TO 0.0.
            SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.0.
            log_info("UPEG", "SECO! Target orbit achieved (" + upeg_state["cutoff_reason"] + ").").
            log_info("UPEG", "Final Orbit: " + ROUND(SHIP:OBT:PERIAPSIS / 1000.0, 2) + " km x " +
                             ROUND(SHIP:OBT:APOAPSIS / 1000.0, 2) + " km | Inc: " +
                             ROUND(SHIP:OBT:INCLINATION, 2) + " deg").
            SET mission_active TO FALSE.
        }
    }

    IF TIME:SECONDS - start_time > cfg["MAX_ASCENT_TIME"] {
        log_warn("ASCENT", "Ascent time guard exceeded. Releasing controls.").
        SET mission_active TO FALSE.
    }

    IF TIME:SECONDS - hud_time > 0.2 {
        SET hud_time TO TIME:SECONDS.
        LOCAL hud_mode IS "ASCENT-S1".
        LOCAL hud_fuel IS s1_fuel.
        LOCAL hud_tgo IS t_go_meco.
        IF fsm["current_state"] = "ST_S2_CLEARANCE" OR fsm["current_state"] = "ST_S2_UPEG" {
            SET hud_mode TO "UPEG-S2".
            SET hud_fuel TO SHIP:MASS.
            SET hud_tgo TO upeg_state["t_go"].
        }
        render_hud(fsm["current_state"], radar_alt, vert_speed, horiz_speed,
                   ascent_throttle, hud_mode, hud_fuel, hud_tgo).
    }
    WAIT 0.02.
}

SET SHIP:CONTROL:FORE TO 0.0.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.0.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
UNLOCK THROTTLE.
UNLOCK STEERING.
STEERINGMANAGER:RESETTODEFAULT().
SET CONFIG:IPU TO old_ipu.
log_info("ASCENT", "Ascent guidance terminated. All flight locks released.").