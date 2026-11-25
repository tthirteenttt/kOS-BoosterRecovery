// ============================================================================
// Terminal Hoverslam Guidance v2.2 —— Real-FAR Calibrated Cascade + Flare Loop
// Guarantees centered barge/pad arrival, soft touchdown & upright settling
// ============================================================================

FUNCTION calculate_hoverslam_trigger {
    PARAMETER radar_alt, vert_speed, max_accel, margin_dist, horiz_speed IS 0.0.

    IF radar_alt > 5000.0 OR vert_speed >= 0.0 {
        RETURN FALSE.
    }

    LOCAL grav0 IS SHIP:BODY:MU / (SHIP:BODY:RADIUS * SHIP:BODY:RADIUS).
    LOCAL trig_alt IS solve_hoverslam_ignition_alt(
        vert_speed, horiz_speed, max_accel, grav0, margin_dist, 2.0
    ).
    RETURN radar_alt <= trig_alt.
}

FUNCTION solve_hoverslam_throttle {
    PARAMETER radar_alt, vert_speed, target_td_vel, min_throt, max_throt, tilt_cos IS 1.0.

    IF vert_speed >= target_td_vel {
        RETURN 0.01.
    }

    LOCAL grav0 IS SHIP:BODY:MU / (SHIP:BODY:RADIUS * SHIP:BODY:RADIUS).
    LOCAL h_td IS 0.6.
    LOCAL desired_accel IS solve_hoverslam_req_accel_z(
        radar_alt, vert_speed, target_td_vel, grav0, h_td
    ).

    // Low-altitude closed-loop vertical velocity tracking to cancel RF throttle lag
    IF radar_alt < 25.0 {
        LOCAL td_spd IS ABS(target_td_vel).
        LOCAL a_ref_net IS MAX(3.0, desired_accel - grav0).
        LOCAL v_ref IS -SQRT(td_spd * td_spd + 2.0 * a_ref_net * MAX(0.0, radar_alt - h_td)).
        SET desired_accel TO MAX(0.0, desired_accel + clamp((v_ref - vert_speed) * 1.4, -2.5, 7.0)).
    }

    LOCAL max_thrust IS TUNDRA_F9_PROFILE["ENGINES"]["CENTER"]["MAX_THRUST_ASL"].
    IF SHIP:AVAILABLETHRUST > 100.0 {
        SET max_thrust TO SHIP:AVAILABLETHRUST.
    }
    LOCAL avail_accel IS max_thrust / MAX(SHIP:MASS, 0.001).
    LOCAL vertical_authority IS avail_accel * MAX(MIN(tilt_cos, 1.0), 0.5).

    LOCAL thrust_fraction IS desired_accel / MAX(vertical_authority, 0.001).
    LOCAL eff_min_throt IS MIN(min_throt, 0.39).
    RETURN rf_thrust_frac_to_cmd(thrust_fraction, eff_min_throt, max_throt).
}

FUNCTION calculate_landing_steering {
    PARAMETER landing_cfg, target_geo, radar_alt, ref_horiz IS V(0, 0, 0).

    LOCAL cn_land IS 3.9.
    LOCAL cd_pow IS 0.14.
    LOCAL max_tilt_cfg IS 32.0.
    LOCAL max_aoa_cfg IS 20.0.
    LOCAL pol_min_eta IS 0.10.
    LOCAL pol_full_eta IS 0.35.
    LOCAL align_gate_alt IS 28.0.
    LOCAL upright_lock_alt IS 12.0.
    LOCAL vel_tau IS 1.05.
    LOCAL flare_tau IS 1.8.
    IF landing_cfg:HASKEY("CN_ALPHA_LAND")     { SET cn_land TO landing_cfg["CN_ALPHA_LAND"]. }
    IF landing_cfg:HASKEY("CD_POWERED")        { SET cd_pow TO landing_cfg["CD_POWERED"]. }
    IF landing_cfg:HASKEY("MAX_TILT_DEG")      { SET max_tilt_cfg TO landing_cfg["MAX_TILT_DEG"]. }
    IF landing_cfg:HASKEY("MAX_AOA_DEG")       { SET max_aoa_cfg TO landing_cfg["MAX_AOA_DEG"]. }
    IF landing_cfg:HASKEY("POLARITY_MIN_ETA")  { SET pol_min_eta TO landing_cfg["POLARITY_MIN_ETA"]. }
    IF landing_cfg:HASKEY("POLARITY_FULL_ETA") { SET pol_full_eta TO landing_cfg["POLARITY_FULL_ETA"]. }
    IF landing_cfg:HASKEY("ALIGN_GATE_ALT")    { SET align_gate_alt TO landing_cfg["ALIGN_GATE_ALT"]. }
    IF landing_cfg:HASKEY("UPRIGHT_LOCK_ALT")  { SET upright_lock_alt TO landing_cfg["UPRIGHT_LOCK_ALT"]. }
    IF landing_cfg:HASKEY("VEL_TAU_S")         { SET vel_tau TO landing_cfg["VEL_TAU_S"]. }
    IF landing_cfg:HASKEY("FLARE_TAU_S")       { SET flare_tau TO landing_cfg["FLARE_TAU_S"]. }

    LOCAL v_srf IS SHIP:VELOCITY:SURFACE.
    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL horiz_vel IS v_srf - (v_srf * up_vec) * up_vec.
    LOCAL vert_speed IS SHIP:VERTICALSPEED.

    // 1. Guaranteed vertical settling column well above ground/ASDS deck
    IF radar_alt <= upright_lock_alt OR vert_speed >= -1.0 {
        RETURN make_glide_attitude(up_vec, ref_horiz).
    }

    LOCAL retro IS safe_normalize(-v_srf, up_vec).
    LOCAL f_max_asl_n IS 848000.0.
    LOCAL min_throt_frac IS 0.361.
    LOCAL td_vel IS 1.2.
    IF DEFINED TUNDRA_F9_PROFILE {
        SET f_max_asl_n TO TUNDRA_F9_PROFILE["ENGINES"]["CENTER"]["MAX_THRUST_ASL"] * 1000.0.
        SET min_throt_frac TO MIN(TUNDRA_F9_PROFILE["ENGINES"]["CENTER"]["MIN_THROTTLE"], 0.39).
        SET td_vel TO ABS(TUNDRA_F9_PROFILE["TOUCHDOWN_VELOCITY"]).
    }

    // 2. Smooth dimensionless spool-up guard + real-FAR live aero-TVC polarity margin
    LOCAL s_ref IS 8.25.
    LOCAL f_live_n IS SHIP:THRUST * 1000.0.
    LOCAL w_spool IS hermite_step((f_live_n / MAX(f_max_asl_n, 1000.0) - 0.12) / 0.15).
    LOCAL q_pa IS SHIP:Q * CONSTANT:ATMtokPa * 1000.0.
    LOCAL f_aero_slope IS q_pa * s_ref * cn_land.
    LOCAL f_net_slope IS f_live_n - f_aero_slope.
    LOCAL eta_t IS safe_divide(f_net_slope, f_live_n, 0.0).
    LOCAL w_pol IS w_spool * hermite_step((eta_t - pol_min_eta) / MAX(pol_full_eta - pol_min_eta, 0.05)).
    IF w_pol <= 0.001 {
        RETURN make_glide_attitude(retro, ref_horiz).
    }

    // 3. Exact vertical kinematics -> time-to-alignment-gate (accounts for min-throttle floor)
    LOCAL grav0 IS SHIP:BODY:MU / (SHIP:BODY:RADIUS * SHIP:BODY:RADIUS).
    LOCAL h_td IS 0.6.
    LOCAL m_kg IS MAX(SHIP:MASS * 1000.0, 1000.0).
    LOCAL v_mag IS MAX(v_srf:MAG, 0.5).
    LOCAL eff_alt_td IS MAX(0.5, radar_alt - h_td).
    LOCAL a_kin_z IS MAX(0.0, (vert_speed * vert_speed - td_vel * td_vel) / (2.0 * eff_alt_td)).
    LOCAL a_min_z IS (f_max_asl_n * min_throt_frac) / m_kg - grav0.
    LOCAL a_eff_z IS MAX(a_kin_z, MAX(a_min_z, 0.8)).
    LOCAL vz_gate IS SQRT(td_vel * td_vel + 2.0 * a_eff_z * MAX(0.0, align_gate_alt - h_td)).
    LOCAL t_gate IS 0.0.
    IF radar_alt > align_gate_alt {
        SET t_gate TO (2.0 * (radar_alt - align_gate_alt)) / MAX(ABS(vert_speed) + vz_gate, 1.0).
    }

    // 4. Smooth C1 zenith tilt corridor (32 deg high-alt -> 10 deg at gate -> 0 deg at upright lock)
    LOCAL tilt_cap_deg IS 10.0 * hermite_step((radar_alt - upright_lock_alt) / MAX(align_gate_alt - upright_lock_alt, 6.0)) +
                          MAX(0.0, max_tilt_cfg - 10.0) * hermite_step((radar_alt - align_gate_alt) / 120.0).

    // 5. Bandwidth-Scheduled (6/t^2, -4/t) ZEM + C1 Linear-Parabolic Stopping Envelope
    LOCAL a_thr_live IS MAX(f_live_n / m_kg, 1.0).
    LOCAL a_aero_slp IS f_aero_slope / m_kg.
    LOCAL a_net_eff IS MAX(a_thr_live - a_aero_slp, 0.25 * a_thr_live).
    LOCAL a_thr_term IS MAX((f_max_asl_n * min_throt_frac) / m_kg, grav0).
    LOCAL a_thr_brake_ref IS MAX(0.75 * a_thr_live, a_thr_term).
    LOCAL a_brake IS 0.85 * MIN(a_net_eff, a_thr_brake_ref) * SIN(MIN(max_tilt_cfg, 26.0)).

    LOCAL raw_tgt IS target_geo:POSITION.
    LOCAL dr_horiz IS raw_tgt - (raw_tgt * up_vec) * up_vec.
    LOCAL d_mag IS dr_horiz:MAG.
    LOCAL v_des IS V(0, 0, 0).
    LOCAL a_ff IS V(0, 0, 0).
    IF d_mag > 0.02 AND t_gate > 0.05 {
        LOCAL u_r IS dr_horiz / d_mag.
        LOCAL d_lin IS a_brake * flare_tau * flare_tau.
        LOCAL v_stop IS 0.0.
        IF d_mag <= d_lin {
            SET v_stop TO d_mag / flare_tau.
        } ELSE {
            SET v_stop TO SQRT(2.0 * a_brake * (d_mag - 0.5 * d_lin)).
        }
        LOCAL v_nom IS (1.5 * d_mag) / MAX(t_gate, flare_tau).
        LOCAL v_time IS a_brake * t_gate.
        LOCAL v_mag_des IS MIN(v_nom, MIN(v_stop, v_time)).
        SET v_des TO u_r * v_mag_des.

        LOCAL w_close IS hermite_step((6.0 - t_gate) / 3.0).
        LOCAL slope_dv_dd IS 1.0 / flare_tau.
        IF d_mag > d_lin {
            SET slope_dv_dd TO a_brake / MAX(v_stop, 0.5).
        }
        SET a_ff TO u_r * (-MIN(a_brake, slope_dv_dd * v_mag_des) * 0.70 * w_close).
    }

    // 6. Bandwidth-scheduled velocity loop + real powered retropropulsion drag cancellation
    LOCAL kv_gain IS 1.0 / MAX(vel_tau, 0.25 * MAX(t_gate, vel_tau)).
    LOCAL a_drag_h IS -horiz_vel * ((q_pa * cd_pow * s_ref) / (m_kg * v_mag)).
    LOCAL a_h_req IS (v_des - horiz_vel) * kv_gain + a_ff - a_drag_h.

    // 7. Exact singularity-free 3D aero-thrust force inversion
    LOCAL retro_h IS retro - (retro * up_vec) * up_vec.
    LOCAL b_h IS (a_h_req - retro_h * a_aero_slp) * (1.0 / a_net_eff).
    SET b_h TO b_h - (b_h * up_vec) * up_vec.
    LOCAL sin_tilt_max IS SIN(tilt_cap_deg).
    IF b_h:MAG > sin_tilt_max {
        SET b_h TO b_h:NORMALIZED * sin_tilt_max.
    }
    LOCAL b_z IS SQRT(MAX(0.01, 1.0 - (b_h * b_h))).
    LOCAL desired IS (up_vec * b_z + b_h):NORMALIZED.

    // 8. Physical q-dependent AoA envelope around retro + strict upright corridor
    LOCAL w_aero_q IS hermite_step((q_pa - 1500.0) / 3500.0).
    LOCAL max_aoa_eff IS (MIN(max_aoa_cfg, 22.0) * w_pol) * w_aero_q + 45.0 * (1.0 - w_aero_q) * w_spool.
    LOCAL cur_aoa IS VANG(retro, desired).
    IF cur_aoa > max_aoa_eff AND cur_aoa > 0.01 {
        LOCAL perp_vec IS vxcl(retro, desired).
        IF perp_vec:MAG > 0.0001 {
            SET desired TO (retro * COS(max_aoa_eff) + perp_vec:NORMALIZED * SIN(max_aoa_eff)):NORMALIZED.
        }
    }

    IF VANG(up_vec, desired) > tilt_cap_deg {
        LOCAL h_des IS vxcl(up_vec, desired).
        IF h_des:MAG > 0.0001 {
            SET desired TO (up_vec * COS(tilt_cap_deg) + h_des:NORMALIZED * SIN(tilt_cap_deg)):NORMALIZED.
        } ELSE {
            SET desired TO up_vec.
        }
    }

    RETURN make_glide_attitude(desired, ref_horiz).
}
