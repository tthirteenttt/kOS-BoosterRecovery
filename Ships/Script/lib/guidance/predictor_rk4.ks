// ============================================================================
// RK4 Full-Trajectory Coupled Predictor (predictor_rk4.ks) v1.0
// Uses shared aero_atmo.ks physics (C1 Cd(Mach), true sound speed, Hoverslam)
// ============================================================================

FUNCTION make_prediction_params {
    PARAMETER pred_cfg, sim_eb IS FALSE, guide_cfg IS LEXICON(), override_mass_kg IS -1.0, sim_hs IS TRUE, override_dry_kg IS -1.0.

    LOCAL spin_vec IS SHIP:BODY:ANGULARVEL.
    LOCAL ship_mass_kg IS MAX(SHIP:MASS * 1000.0, 1.0).
    IF override_mass_kg > 1000.0 {
        SET ship_mass_kg TO override_mass_kg.
    }
    LOCAL area_m2 IS pred_cfg["DRAG_AREA"].

    LOCAL f3_vac_kn IS 2742.36.
    LOCAL f3_asl_kn IS 2544.00.
    LOCAL isp3_vac IS 311.0.
    LOCAL min_throt3 IS 0.361.
    LOCAL f1_asl_kn IS 848.00.
    LOCAL isp1_asl IS 288.5.
    LOCAL min_throt1 IS 0.361.
    LOCAL gear_offset IS 43.5.
    LOCAL td_vel IS 1.2.
    LOCAL dry_mass_kg IS 22200.0.
    IF DEFINED TUNDRA_F9_PROFILE {
        LOCAL eng3 IS TUNDRA_F9_PROFILE["ENGINES"]["THREE"].
        SET f3_vac_kn TO eng3["MAX_THRUST_VAC"].
        SET f3_asl_kn TO eng3["MAX_THRUST_ASL"].
        SET isp3_vac TO eng3["ISP_VAC"].
        SET min_throt3 TO eng3["MIN_THROTTLE"].
        LOCAL eng1 IS TUNDRA_F9_PROFILE["ENGINES"]["CENTER"].
        SET f1_asl_kn TO eng1["MAX_THRUST_ASL"].
        IF eng1:HASKEY("ISP_ASL") { SET isp1_asl TO eng1["ISP_ASL"]. }
        SET min_throt1 TO MIN(eng1["MIN_THROTTLE"], 0.39).
        SET gear_offset TO TUNDRA_F9_PROFILE["LANDING_GEAR_OFFSET"].
        SET td_vel TO ABS(TUNDRA_F9_PROFILE["TOUCHDOWN_VELOCITY"]).
        IF TUNDRA_F9_PROFILE:HASKEY("S1_DRY_MASS") {
            SET dry_mass_kg TO TUNDRA_F9_PROFILE["S1_DRY_MASS"] * 1000.0.
        }
    }
    IF override_dry_kg > 1000.0 {
        SET dry_mass_kg TO override_dry_kg.
    }

    LOCAL eb_cmd_throt IS 0.90.
    LOCAL eb_start_alt IS 66200.0.
    LOCAL eb_end_alt IS 36000.0.
    LOCAL eb_end_spd IS 700.0.
    LOCAL eb_min_prop_kg IS 4600.0.
    LOCAL hs_margin IS 30.0.
    IF guide_cfg:HASKEY("ENTRY_BURN_THROTTLE") {
        SET eb_cmd_throt TO guide_cfg["ENTRY_BURN_THROTTLE"].
        SET eb_start_alt TO guide_cfg["COAST_ENTRY_ALT"] - 1800.0.
        SET eb_end_alt TO guide_cfg["ENTRY_BURN_END_ALT"].
        SET eb_end_spd TO guide_cfg["ENTRY_BURN_END_SPEED"].
    }
    IF guide_cfg:HASKEY("EB_MIN_LANDING_PROP_T") {
        SET eb_min_prop_kg TO guide_cfg["EB_MIN_LANDING_PROP_T"] * 1000.0.
    }
    IF guide_cfg:HASKEY("HOVERSLAM_MARGIN") {
        SET hs_margin TO guide_cfg["HOVERSLAM_MARGIN"].
    }

    LOCAL rf_frac IS rf_throttle_to_thrust_frac(eb_cmd_throt, min_throt3).
    LOCAL f3_vac_newtons IS f3_vac_kn * 1000.0 * rf_frac.
    LOCAL f3_asl_newtons IS f3_asl_kn * 1000.0 * rf_frac.
    LOCAL mdot_eb_kgs IS f3_vac_newtons / (isp3_vac * 9.80665).

    LOCAL step_cap IS MAX(1, pred_cfg["MAX_STEPS"]).
    IF sim_hs { SET step_cap TO MAX(step_cap, 220). }

    RETURN LEXICON(
        "MU", SHIP:BODY:MU,
        "R_BODY", SHIP:BODY:RADIUS,
        "OMEGA", spin_vec,
        "ATM_TOP", pred_cfg["ATM_TOP"],
        "DRAG_AREA", area_m2,
        "MASS_INIT_KG", ship_mass_kg,
        "DRY_MASS_KG", dry_mass_kg,
        "AREA_OVER_MASS", area_m2 / ship_mass_kg,
        "BASE_CD", pred_cfg["DRAG_CD"],
        "GROUND", SHIP:BODY:RADIUS + pred_cfg["MIN_ALT"],
        "MAX_STEPS", step_cap,
        "DT", MAX(0.01, pred_cfg["DT"]),
        "ROTATION_SIGN", pred_cfg["ROTATION_SIGN"],
        "SIM_EB", sim_eb,
        "EB_START_ALT", eb_start_alt,
        "EB_END_ALT", eb_end_alt,
        "EB_END_SPD", eb_end_spd,
        "EB_MIN_PROP_KG", eb_min_prop_kg,
        "EB_THRUST_N", f3_vac_newtons,
        "EB_ASL_N", f3_asl_newtons,
        "EB_MDOT_KGS", mdot_eb_kgs,
        "SIM_HS", sim_hs,
        "F1_ASL_N", f1_asl_kn * 1000.0,
        "F1_MIN_FRAC", min_throt1,
        "ISP1_ASL", isp1_asl,
        "HS_MARGIN", hs_margin,
        "HS_SPOOL_S", 1.75,
        "CD_POWERED", 0.14,
        "GEAR_OFFSET", gear_offset,
        "HS_TD_VEL", td_vel
    ).
}

FUNCTION rk4_atmospheric_accel {
    PARAMETER r_pos, v_vel, p, current_mass_kg IS -1.0, eb_active IS FALSE, hs_thrust_n IS 0.0.

    LOCAL r_mag IS MAX(r_pos:MAG, 1.0).
    LOCAL grav_vec IS r_pos * (-p["MU"] / (r_mag * r_mag * r_mag)).
    LOCAL omega_vec IS p["OMEGA"].
    LOCAL v_rot_surface IS VCRS(omega_vec, r_pos).
    LOCAL v_air IS v_vel - v_rot_surface.
    LOCAL h_agl IS r_mag - p["R_BODY"].

    LOCAL m_kg IS p["MASS_INIT_KG"].
    IF current_mass_kg > 100.0 {
        SET m_kg TO current_mass_kg.
    }
    LOCAL area_over_m IS p["DRAG_AREA"] / m_kg.
    LOCAL dens IS lookup_atmospheric_density(h_agl, p["ATM_TOP"]).

    LOCAL drag_vec IS V(0, 0, 0).
    LOCAL v_air_mag IS v_air:MAG.
    IF dens > 0.000001 AND v_air_mag > 0.001 {
        LOCAL cd_eff IS 0.14.
        IF hs_thrust_n > 0.0 {
            IF p:HASKEY("CD_POWERED") { SET cd_eff TO p["CD_POWERED"]. }
        } ELSE {
            LOCAL a_snd IS lookup_rss_sound_speed(h_agl).
            LOCAL mach_est IS v_air_mag / a_snd.
            SET cd_eff TO compute_booster_cd(mach_est, p["BASE_CD"], 0.0).
        }
        SET drag_vec TO v_air * (-0.5 * dens * v_air_mag * cd_eff * area_over_m).
    }

    LOCAL thrust_vec IS V(0, 0, 0).
    IF eb_active AND v_air_mag > 1.0 {
        LOCAL p_atm_eb IS SHIP:BODY:ATM:ALTITUDEPRESSURE(MAX(0.0, h_agl)).
        LOCAL eb_thr_n IS rf_pressure_thrust_n(p["EB_THRUST_N"], p["EB_ASL_N"], p_atm_eb).
        SET thrust_vec TO (-v_air / v_air_mag) * (eb_thr_n / m_kg).
    } ELSE IF hs_thrust_n > 0.0 {
        LOCAL hs_dir IS r_pos / r_mag.
        IF v_air_mag > 2.0 { SET hs_dir TO -v_air / v_air_mag. }
        SET thrust_vec TO hs_dir * (hs_thrust_n / m_kg).
    }

    RETURN grav_vec + drag_vec + thrust_vec.
}

FUNCTION predict_impact_state {
    PARAMETER p, r_init IS V(0, 0, 0), v_init IS V(0, 0, 0), t_offset IS 0.0.

    LOCAL r_pos IS SHIP:POSITION - SHIP:BODY:POSITION.
    LOCAL v_vel IS SHIP:VELOCITY:ORBIT.
    IF r_init:MAG > 1000.0 {
        SET r_pos TO r_init.
        SET v_vel TO v_init.
    }

    LOCAL m_kg IS p["MASS_INIT_KG"].
    LOCAL dry_m_kg IS 22200.0.
    IF p:HASKEY("DRY_MASS_KG") { SET dry_m_kg TO p["DRY_MASS_KG"]. }
    LOCAL eb_min_prop_kg IS 4600.0.
    IF p:HASKEY("EB_MIN_PROP_KG") { SET eb_min_prop_kg TO p["EB_MIN_PROP_KG"]. }
    LOCAL dt_base IS p["DT"].
    LOCAL flight_time IS 0.0.
    LOCAL step_count IS 0.
    LOCAL ground_r IS p["GROUND"].
    LOCAL grav_srf IS p["MU"] / (p["R_BODY"] * p["R_BODY"]).
    LOCAL impact_r IS r_pos.
    LOCAL found IS FALSE.

    LOCAL sim_eb IS FALSE.
    IF p:HASKEY("SIM_EB") { SET sim_eb TO p["SIM_EB"]. }
    LOCAL eb_done IS FALSE.
    LOCAL eb_end_alt_m IS 0.0.
    LOCAL eb_end_spd_ms IS 0.0.
    LOCAL eb_end_reason IS "NONE".

    LOCAL sim_hs IS FALSE.
    IF p:HASKEY("SIM_HS") { SET sim_hs TO p["SIM_HS"]. }
    LOCAL gear_off IS 43.5.
    IF p:HASKEY("GEAR_OFFSET") { SET gear_off TO p["GEAR_OFFSET"]. }
    LOCAL hs_spool_s IS 1.75.
    IF p:HASKEY("HS_SPOOL_S") { SET hs_spool_s TO p["HS_SPOOL_S"]. }
    LOCAL hs_triggered IS FALSE.
    LOCAL hs_spool_t IS 0.0.
    LOCAL stop_r IS ground_r.
    IF sim_hs { SET stop_r TO ground_r + gear_off + 0.6. }

    LOCAL init_air IS v_vel - VCRS(p["OMEGA"], r_pos).
    LOCAL init_vh_vec IS vxcl(r_pos:NORMALIZED, init_air).
    LOCAL vh_at_3km IS init_vh_vec:MAG.
    LOCAL vh_dir_3km IS safe_normalize(init_vh_vec, V(1, 0, 0)).
    LOCAL v_at_3km IS init_air:MAG.
    LOCAL vz_at_3km IS (init_air * r_pos) / MAX(r_pos:MAG, 1.0).
    LOCAL max_q_kpa IS 0.0.
    LOCAL max_g IS 0.0.
    LOCAL max_alt_m IS r_pos:MAG - p["R_BODY"].
    LOCAL glide_radius_m IS 0.0.
    LOCAL glide_dv_ms IS 0.0.
    LOCAL m_post_eb_kg IS m_kg.

    UNTIL found OR step_count >= p["MAX_STEPS"] {
        LOCAL dt_step IS dt_base.
        LOCAL r_mag_cur IS MAX(r_pos:MAG, 1.0).
        LOCAL u_up_cur IS r_pos / r_mag_cur.
        LOCAL h_agl IS r_mag_cur - p["R_BODY"].
        LOCAL h_radar_sim IS r_mag_cur - ground_r - gear_off.
        IF h_agl > max_alt_m { SET max_alt_m TO h_agl. }

        LOCAL v_radial IS v_vel * u_up_cur.
        LOCAL v_air IS v_vel - VCRS(p["OMEGA"], r_pos).
        LOCAL v_air_mag IS v_air:MAG.
        LOCAL vh_vec_cur IS vxcl(u_up_cur, v_air).
        LOCAL vh_cur IS vh_vec_cur:MAG.

        LOCAL dens_cur IS lookup_atmospheric_density(h_agl, p["ATM_TOP"]).
        LOCAL q_kpa_cur IS 0.5 * dens_cur * v_air_mag * v_air_mag * 0.001.
        IF q_kpa_cur > max_q_kpa { SET max_q_kpa TO q_kpa_cur. }
        IF dens_cur > 0.000001 {
            LOCAL a_drag_est IS (q_kpa_cur * 1000.0 * p["BASE_CD"] * p["DRAG_AREA"]) / MAX(m_kg, 1000.0).
            LOCAL g_cur IS a_drag_est / 9.80665.
            IF g_cur > max_g { SET max_g TO g_cur. }
        }
        IF h_agl > 3000.0 {
            SET vh_at_3km TO vh_cur.
            SET v_at_3km TO v_air_mag.
            SET vz_at_3km TO v_radial.
            IF vh_cur > 1.0 { SET vh_dir_3km TO vh_vec_cur / vh_cur. }
        }

        // Phase 3: Coupled Entry Burn
        LOCAL eb_step_active IS FALSE.
        IF sim_eb AND (NOT eb_done) AND v_radial < 0.0 {
            IF h_agl > p["EB_START_ALT"] {
                LOCAL dt_to_eb IS (h_agl - p["EB_START_ALT"]) / MAX(-v_radial, 1.0).
                IF dt_to_eb < dt_step {
                    SET dt_step TO MAX(0.05, dt_to_eb + 0.02).
                }
            } ELSE {
                IF h_agl <= p["EB_END_ALT"] OR v_air_mag <= p["EB_END_SPD"] OR m_kg <= (dry_m_kg + eb_min_prop_kg) {
                    SET eb_done TO TRUE.
                    SET m_post_eb_kg TO m_kg.
                    SET eb_end_alt_m TO h_agl.
                    SET eb_end_spd_ms TO v_air_mag.
                    IF h_agl <= p["EB_END_ALT"] {
                        SET eb_end_reason TO "ALT".
                    } ELSE IF v_air_mag <= p["EB_END_SPD"] {
                        SET eb_end_reason TO "SPD".
                    } ELSE {
                        SET eb_end_reason TO "FUEL".
                    }
                } ELSE {
                    SET eb_step_active TO TRUE.
                    LOCAL a_eb_est IS (p["EB_THRUST_N"] / m_kg) - 9.2.
                    LOCAL dt_to_spd IS (v_air_mag - p["EB_END_SPD"]) / MAX(a_eb_est, 5.0).
                    LOCAL dt_to_alt IS (h_agl - p["EB_END_ALT"]) / MAX(-v_radial, 1.0).
                    SET dt_step TO MIN(dt_step, MAX(0.05, MIN(dt_to_spd, dt_to_alt))).
                }
            }
        }

        // Phase 5: Coupled Pure-Retrograde Single-Engine Hoverslam (shared aero_atmo helpers)
        LOCAL hs_thrust_n IS 0.0.
        LOCAL hs_mdot_kgs IS 0.0.
        IF sim_hs AND (NOT eb_step_active) AND v_radial < -1.0 {
            IF NOT hs_triggered {
                IF h_radar_sim <= 5000.0 {
                    LOCAL a_max_hs IS p["F1_ASL_N"] / MAX(m_kg, 1000.0).
                    LOCAL h_trig_hs IS solve_hoverslam_ignition_alt(
                        v_radial, vh_cur, a_max_hs, grav_srf, p["HS_MARGIN"], 2.0
                    ).
                    IF h_radar_sim <= h_trig_hs {
                        SET hs_triggered TO TRUE.
                        SET hs_spool_t TO 0.0.
                    } ELSE {
                        LOCAL dt_to_hs IS (h_radar_sim - h_trig_hs) / MAX(-v_radial, 1.0).
                        IF dt_to_hs < dt_step {
                            SET dt_step TO MAX(0.05, dt_to_hs + 0.02).
                        }
                    }
                }
            }
            IF hs_triggered {
                IF hs_spool_t < hs_spool_s {
                    SET dt_step TO MIN(dt_step, MAX(0.05, hs_spool_s - hs_spool_t)).
                } ELSE IF m_kg > (dry_m_kg + 100.0) {
                    SET dt_step TO MIN(dt_step, 1.2).
                    IF h_radar_sim < 350.0 { SET dt_step TO MIN(dt_step, 0.5). }
                    LOCAL des_az_hs IS solve_hoverslam_req_accel_z(
                        h_radar_sim, v_radial, p["HS_TD_VEL"], grav_srf
                    ).
                    LOCAL t_cos_hs IS MAX(0.5, MIN(1.0, ABS(v_radial) / MAX(v_air_mag, 0.1))).
                    LOCAL f_req_hs IS (m_kg * des_az_hs) / t_cos_hs.
                    LOCAL f_min_hs IS p["F1_ASL_N"] * p["F1_MIN_FRAC"].
                    LOCAL f_max_hs IS p["F1_ASL_N"] * 0.98.
                    SET hs_thrust_n TO clamp(f_req_hs, f_min_hs, f_max_hs).
                    SET hs_mdot_kgs TO hs_thrust_n / (p["ISP1_ASL"] * 9.80665).
                }
            }
        }

        LOCAL m_mid IS m_kg.
        LOCAL m_end IS m_kg.
        IF eb_step_active {
            SET m_mid TO MAX(dry_m_kg + 1800.0, m_kg - p["EB_MDOT_KGS"] * (dt_step * 0.5)).
            SET m_end TO MAX(dry_m_kg + 1800.0, m_kg - p["EB_MDOT_KGS"] * dt_step).
        } ELSE IF hs_mdot_kgs > 0.0 {
            SET m_mid TO MAX(dry_m_kg, m_kg - hs_mdot_kgs * (dt_step * 0.5)).
            SET m_end TO MAX(dry_m_kg, m_kg - hs_mdot_kgs * dt_step).
        }

        LOCAL k1r IS v_vel.
        LOCAL k1v IS rk4_atmospheric_accel(r_pos, v_vel, p, m_kg, eb_step_active, hs_thrust_n).
        LOCAL k2r IS v_vel + k1v * (dt_step * 0.5).
        LOCAL k2v IS rk4_atmospheric_accel(r_pos + k1r * (dt_step * 0.5), k2r, p, m_mid, eb_step_active, hs_thrust_n).
        LOCAL k3r IS v_vel + k2v * (dt_step * 0.5).
        LOCAL k3v IS rk4_atmospheric_accel(r_pos + k2r * (dt_step * 0.5), k3r, p, m_mid, eb_step_active, hs_thrust_n).
        LOCAL k4r IS v_vel + k3v * dt_step.
        LOCAL k4v IS rk4_atmospheric_accel(r_pos + k3r * dt_step, k4r, p, m_end, eb_step_active, hs_thrust_n).

        LOCAL r_next IS r_pos + (k1r + k2r * 2.0 + k3r * 2.0 + k4r) * (dt_step / 6.0).
        LOCAL v_next IS v_vel + (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (dt_step / 6.0).
        SET m_kg TO m_end.
        IF eb_step_active { SET m_post_eb_kg TO m_kg. }
        IF hs_triggered { SET hs_spool_t TO hs_spool_t + dt_step. }

        IF (NOT eb_step_active) AND (NOT hs_triggered) AND v_radial < -5.0 AND h_agl <= 38000.0 AND h_radar_sim > 2500.0 {
            LOCAL a_snd_gl IS lookup_rss_sound_speed(h_agl).
            LOCAL mach_gl IS v_air_mag / a_snd_gl.
            LOCAL cd_gl IS compute_booster_cd(mach_gl, p["BASE_CD"], 0.0).
            LOCAL ld_gl IS 0.14.
            IF mach_gl < 0.85 {
                SET ld_gl TO 0.24.
            } ELSE IF mach_gl < 1.85 {
                SET ld_gl TO 0.18.
            }
            LOCAL a_d_gl IS (0.5 * dens_cur * v_air_mag * v_air_mag * cd_gl * p["DRAG_AREA"]) / MAX(m_kg, 1000.0).
            LOCAL lam_gl IS a_d_gl / MAX(v_air_mag, 10.0).
            LOCAL v_eq_gl IS ld_gl * ABS(v_radial).
            LOCAL dv_next_gl IS v_eq_gl + (glide_dv_ms - v_eq_gl) * (CONSTANT:E ^ (-lam_gl * dt_step)).
            SET glide_radius_m TO glide_radius_m + 0.5 * (glide_dv_ms + dv_next_gl) * dt_step.
            SET glide_dv_ms TO dv_next_gl.
        }

        LOCAL v_rad_next IS (v_next * r_next) / MAX(r_next:MAG, 1.0).
        IF r_next:MAG <= stop_r {
            LOCAL r_prev_mag IS r_pos:MAG.
            LOCAL frac IS (r_prev_mag - stop_r) / MAX(r_prev_mag - r_next:MAG, 0.001).
            SET frac TO MAX(0.0, MIN(1.0, frac)).
            SET impact_r TO r_pos + (r_next - r_pos) * frac.
            SET flight_time TO flight_time + dt_step * frac.
            SET found TO TRUE.
        } ELSE IF hs_triggered AND hs_spool_t >= hs_spool_s AND v_rad_next >= -0.5 {
            SET impact_r TO r_next.
            SET flight_time TO flight_time + dt_step.
            SET found TO TRUE.
        } ELSE {
            SET r_pos TO r_next.
            SET v_vel TO v_next.
            SET flight_time TO flight_time + dt_step.
        }
        SET step_count TO step_count + 1.
    }

    IF NOT found {
        SET impact_r TO r_pos.
    }

    LOCAL total_time IS t_offset + flight_time.
    LOCAL spin_vec IS p["OMEGA"].
    LOCAL body_fixed IS impact_r.
    LOCAL vh_fixed IS vh_dir_3km.
    IF spin_vec:MAG > 0.000000001 {
        LOCAL spin_deg IS spin_vec:MAG * (180.0 / CONSTANT:PI) * total_time * p["ROTATION_SIGN"].
        LOCAL rot_q IS ANGLEAXIS(spin_deg, spin_vec:NORMALIZED).
        SET body_fixed TO rot_q * impact_r.
        SET vh_fixed TO (rot_q * vh_dir_3km):NORMALIZED.
    }

    LOCAL impact_geo IS SHIP:BODY:GEOPOSITIONOF(SHIP:BODY:POSITION + body_fixed).
    LOCAL dynamic_lead_m IS 0.0.
    LOCAL asds_fixed IS body_fixed.
    IF NOT sim_hs {
        SET dynamic_lead_m TO clamp(vh_at_3km * 1.4, 30.0, 110.0).
        SET asds_fixed TO body_fixed - vh_fixed * dynamic_lead_m.
    }
    LOCAL asds_geo IS SHIP:BODY:GEOPOSITIONOF(SHIP:BODY:POSITION + asds_fixed).

    RETURN LEXICON(
        "GEO", impact_geo,
        "ASDS_GEO", asds_geo,
        "ASDS_FIXED", asds_fixed,
        "TIME", flight_time,
        "TOTAL_TIME", total_time,
        "OK", found,
        "STEPS", step_count,
        "LEAD_M", dynamic_lead_m,
        "MAX_Q_KPA", max_q_kpa,
        "MAX_G", max_g,
        "MAX_ALT_M", max_alt_m,
        "M_POST_EB_KG", m_post_eb_kg,
        "EB_END_ALT", eb_end_alt_m,
        "EB_END_SPD", eb_end_spd_ms,
        "EB_END_REASON", eb_end_reason,
        "V_3KM", v_at_3km,
        "VZ_3KM", vz_at_3km,
        "VH_3KM", vh_at_3km,
        "GLIDE_RADIUS_M", glide_radius_m
    ).
}
