// ============================================================================
// Aerodynamic Glide Guidance (aero_guide.ks) v1.1 —— Unified Authority-Normalized
// Adapts seamlessly across Shallow Cape ASDS, Steep Vandenberg SSO ASDS & RTLS
// ============================================================================

FUNCTION make_glide_attitude {
    PARAMETER steer_vec, ref_horiz IS V(0, 0, 0).

    IF ref_horiz:MAG > 0.1 {
        LOCAL ang_ref IS VANG(steer_vec, ref_horiz).
        IF ang_ref > 20.0 AND ang_ref < 160.0 {
            LOCAL top_h IS vxcl(steer_vec, ref_horiz).
            IF top_h:MAG > 0.001 {
                RETURN LOOKDIRUP(steer_vec, top_h:NORMALIZED).
            }
        }
    }

    LOCAL top_vec IS vxcl(steer_vec, SHIP:UP:VECTOR).
    IF top_vec:MAG < 0.001 {
        SET top_vec TO vxcl(steer_vec, SHIP:NORTH:VECTOR).
    }
    RETURN LOOKDIRUP(steer_vec, top_vec:NORMALIZED).
}

FUNCTION init_aero_guidance {
    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL v_srf IS SHIP:VELOCITY:SURFACE.
    LOCAL retro IS safe_normalize(-v_srf, up_vec).
    LOCAL ref_h IS safe_normalize(vxcl(up_vec, v_srf), SHIP:NORTH:VECTOR).
    RETURN LEXICON("STEER", retro, "REF_HORIZ", ref_h).
}

FUNCTION compute_hoverslam_range_lead {
    IF DEFINED pred_lead_m AND pred_lead_m >= 0.0 {
        RETURN pred_lead_m.
    }
    LOCAL vh IS get_horizontal_speed(SHIP:VELOCITY:SURFACE).
    LOCAL vz IS MAX(50.0, ABS(SHIP:VERTICALSPEED)).
    LOCAL glide_ratio IS clamp(vh / vz, 0.15, 0.85).
    RETURN clamp(300.0 * glide_ratio, 50.0, 260.0).
}

FUNCTION calculate_glide_steering {
    PARAMETER target_geo, pred_geo, aero_cfg, down_pid, cross_pid, aero_state, dt IS 0.02, pred_glide_rad_m IS 1000.0.

    LOCAL v_srf IS SHIP:VELOCITY:SURFACE.
    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL retro IS safe_normalize(-v_srf, up_vec).
    LOCAL dyn_q IS SHIP:Q.

    LOCAL horiz_vel IS v_srf - (v_srf * up_vec) * up_vec.
    LOCAL down_axis IS aero_state["REF_HORIZ"].
    IF horiz_vel:MAG > 15.0 {
        SET down_axis TO horiz_vel:NORMALIZED.
        SET aero_state["REF_HORIZ"] TO down_axis.
    }

    IF dyn_q < aero_cfg["MIN_Q_FOR_GLIDE"] {
        SET aero_state["STEER"] TO retro.
        RETURN make_glide_attitude(retro, down_axis).
    }

    LOCAL miss_vec IS target_geo:POSITION - pred_geo:POSITION.
    LOCAL horiz_miss IS miss_vec - (miss_vec * up_vec) * up_vec.

    LOCAL cross_axis IS VCRS(up_vec, down_axis).
    IF cross_axis:MAG < 0.001 {
        SET cross_axis TO SHIP:NORTH:VECTOR.
    } ELSE {
        SET cross_axis TO cross_axis:NORMALIZED.
    }

    LOCAL auto_lead_m IS compute_hoverslam_range_lead().
    LOCAL handoff_bias_m IS 15.0.
    IF aero_cfg:HASKEY("HANDOFF_OVERSHOOT_M") { SET handoff_bias_m TO aero_cfg["HANDOFF_OVERSHOOT_M"]. }
    LOCAL err_down IS (horiz_miss * down_axis) + auto_lead_m + handoff_bias_m.
    LOCAL err_cross IS horiz_miss * cross_axis.

    LOCAL deadband IS MAX(0.0, aero_cfg["DEADBAND_M"]).
    IF ABS(err_down) < deadband { SET err_down TO 0.0. }
    IF ABS(err_cross) < deadband { SET err_cross TO 0.0. }

    // Unified physical remaining-authority normalization across ASDS & RTLS
    LOCAL q_kpa IS dyn_q * CONSTANT:ATMtokPa.
    LOCAL q_scale_kpa IS 0.0.
    IF aero_cfg:HASKEY("Q_SCALE_KPA") { SET q_scale_kpa TO MAX(0.0, aero_cfg["Q_SCALE_KPA"]). }
    LOCAL q_scale IS 1.0 + MAX(0.0, q_kpa) * q_scale_kpa.

    LOCAL auth_min IS 120.0.
    LOCAL auth_max IS 2000.0.
    IF aero_cfg:HASKEY("AUTH_MIN_M") { SET auth_min TO MAX(50.0, aero_cfg["AUTH_MIN_M"]). }
    IF aero_cfg:HASKEY("AUTH_MAX_M") { SET auth_max TO MAX(auth_min, aero_cfg["AUTH_MAX_M"]). }
    LOCAL auth_ref_m IS clamp(pred_glide_rad_m, auth_min, auth_max).

    LOCAL e_down IS err_down / auth_ref_m / MAX(q_scale, 0.001).
    LOCAL e_cross IS err_cross / auth_ref_m / MAX(q_scale, 0.001).

    LOCAL cmd_down IS update_pid(down_pid, e_down).
    LOCAL cmd_cross IS update_pid(cross_pid, e_cross).

    LOCAL pitch_axis IS safe_normalize(vxcl(retro, down_axis), up_vec).
    LOCAL yaw_axis IS safe_normalize(vxcl(retro, cross_axis), SHIP:NORTH:VECTOR).

    LOCAL tilt_vec IS pitch_axis * cmd_down + yaw_axis * cmd_cross.
    LOCAL cfg_max_aoa IS MAX(0.1, MIN(aero_cfg["MAX_AOA_DEG"], 18.0)).

    // Physical q*alpha structural envelope: gently trim above 32 kPa supersonic Max-Q,
    // allow up to 17.5 deg in subsonic low-Q final glide to clear FAR <5 deg deadzone
    IF q_kpa > 32.0 {
        LOCAL hi_q_frac IS clamp((q_kpa - 32.0) / 18.0, 0.0, 1.0).
        SET cfg_max_aoa TO MIN(cfg_max_aoa, 16.0 - 2.5 * hi_q_frac).
    } ELSE IF v_srf:MAG < 750.0 {
        SET cfg_max_aoa TO MIN(17.5, cfg_max_aoa + 1.5).
    }

    LOCAL q_ramp IS MIN(1.0, MAX(0.25, (dyn_q - 0.003) / 0.015)).
    LOCAL max_aoa IS cfg_max_aoa * q_ramp.
    LOCAL cmd_mag IS MIN(max_aoa, tilt_vec:MAG).

    LOCAL raw_desired IS retro.
    IF cmd_mag > 0.01 AND tilt_vec:MAG > 0.0001 {
        LOCAL tilt_unit IS tilt_vec:NORMALIZED.
        SET raw_desired TO (retro - tilt_unit * TAN(cmd_mag)):NORMALIZED.
    }

    LOCAL base_alpha IS clamp(aero_cfg["STEER_SLEW_ALPHA"], 0.05, 0.95).
    LOCAL tau_filter IS -0.02 / LN(1.0 - base_alpha).
    LOCAL eff_alpha IS clamp(1.0 - (CONSTANT:E ^ (-MAX(0.005, dt) / MAX(0.02, tau_filter))), 0.05, 1.0).
    LOCAL prev_steer IS aero_state["STEER"].
    LOCAL smoothed IS (prev_steer * (1.0 - eff_alpha) + raw_desired * eff_alpha):NORMALIZED.

    SET aero_state["STEER"] TO smoothed.
    RETURN make_glide_attitude(smoothed, down_axis).
}