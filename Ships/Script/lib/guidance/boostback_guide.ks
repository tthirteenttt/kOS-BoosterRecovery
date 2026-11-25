// ============================================================================
// Boostback Burn Guidance (boostback_guide.ks)
// ----------------------------------------------------------------------------
// Closed-loop RTLS boostback with dead-reckoning between RK4 predictor ticks,
// ignition-latch protection (prevents multi-ignition loss in RealFuels), and
// smooth distance-based throttle ramp-down.
// ============================================================================

FUNCTION init_boostback_state {
    RETURN LEXICON(
        "INITIALIZED", FALSE,
        "AXIS", SHIP:NORTH:VECTOR,
        "DV_SINCE_PRED", V(0, 0, 0),
        "IGNITION_LATCHED", FALSE,
        "IGNITION_TIME", 0.0
    ).
}

FUNCTION update_boostback_dead_reckoning {
    PARAMETER bb_state, dt, pred_flight_time.

    IF SHIP:THRUST > 1.0 {
        LOCAL a_thrust IS (SHIP:THRUST / MAX(SHIP:MASS, 1.0)) * SHIP:FACING:VECTOR.
        LOCAL a_horiz IS vxcl(SHIP:UP:VECTOR, a_thrust).
        SET bb_state["DV_SINCE_PRED"] TO bb_state["DV_SINCE_PRED"] + a_horiz * dt.
    }
    LOCAL eff_time IS MAX(60.0, pred_flight_time) * 0.72.
    RETURN bb_state["DV_SINCE_PRED"] * eff_time.
}

FUNCTION step_boostback_guidance {
    PARAMETER target_geo, pred_geo, pred_flight_time, dt, bb_state.

    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL dr_reckon IS update_boostback_dead_reckoning(bb_state, dt, pred_flight_time).

    LOCAL est_pred_pos IS pred_geo:POSITION + dr_reckon.
    LOCAL raw_miss IS target_geo:POSITION - est_pred_pos.
    LOCAL horiz_miss IS vxcl(up_vec, raw_miss).

    IF NOT bb_state["INITIALIZED"] AND horiz_miss:MAG > 100.0 {
        SET bb_state["AXIS"] TO horiz_miss:NORMALIZED.
        SET bb_state["INITIALIZED"] TO TRUE.
    }
    LOCAL u_bb IS safe_normalize(vxcl(up_vec, bb_state["AXIS"]), SHIP:NORTH:VECTOR).
    SET bb_state["AXIS"] TO u_bb.

    LOCAL range_lead IS compute_hoverslam_range_lead().
    LOCAL total_horiz_miss IS horiz_miss + u_bb * range_lead.

    LOCAL e_lon IS total_horiz_miss * u_bb.
    LOCAL e_cross_vec IS total_horiz_miss - (u_bb * e_lon).

    // Moderate cross-track gain with 2 km longitudinal floor prevents terminal whip
    LOCAL steer_horiz IS u_bb * MAX(2000.0, e_lon) + e_cross_vec * 2.0.
    LOCAL steer_vec IS safe_normalize(steer_horiz, u_bb).

    LOCAL att_err IS VANG(SHIP:FACING:VECTOR, steer_vec).
    LOCAL py_omega_deg_s IS vxcl(SHIP:FACING:VECTOR, SHIP:ANGULARVEL):MAG * (180.0 / CONSTANT:PI).

    // Latch ignition once attitude error < 32 deg and pitch/yaw rate < 20 deg/s
    IF NOT bb_state["IGNITION_LATCHED"] {
        IF att_err < 32.0 AND py_omega_deg_s < 20.0 {
            STEERINGMANAGER:RESETPIDS().
            SET bb_state["IGNITION_LATCHED"] TO TRUE.
            SET bb_state["IGNITION_TIME"] TO TIME:SECONDS.
            log_info("BOOSTBACK", "Ignition latched (att err " + ROUND(att_err, 1) + " deg).").
        } ELSE {
            RETURN LEXICON(
                "STEER_VEC", steer_vec,
                "THROTTLE", 0.0,
                "CUTOFF", FALSE,
                "LON_ERR", e_lon,
                "CROSS_ERR", e_cross_vec:MAG
            ).
        }
    }

    // Never command 0.0 throttle before cutoff once latched (preserves RF ignition & TVC)
    LOCAL burn_elapsed IS TIME:SECONDS - bb_state["IGNITION_TIME"].
    LOCAL ramp_throt IS clamp(0.05 + (burn_elapsed / 0.8) * 0.95, 0.05, 1.0).
    LOCAL dist_throt IS 1.0.
    IF e_lon < 25000.0 {
        SET dist_throt TO clamp((e_lon - 3000.0) / 22000.0, 0.01, 1.0).
    }
    LOCAL cmd_throt IS MIN(ramp_throt, dist_throt).

    IF att_err > 18.0 {
        SET cmd_throt TO 0.05.
    }

    LOCAL cutoff_reached IS (bb_state["INITIALIZED"] AND e_lon <= 0.0).

    RETURN LEXICON(
        "STEER_VEC", steer_vec,
        "THROTTLE", cmd_throt,
        "CUTOFF", cutoff_reached,
        "LON_ERR", e_lon,
        "CROSS_ERR", e_cross_vec:MAG
    ).
}

FUNCTION calculate_boostback_vector {
    PARAMETER target_geo, pred_geo.
    LOCAL horiz_miss IS vxcl(SHIP:UP:VECTOR, target_geo:POSITION - pred_geo:POSITION).
    RETURN safe_normalize(horiz_miss, -SHIP:VELOCITY:SURFACE).
}
