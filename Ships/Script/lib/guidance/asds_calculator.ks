// ============================================================================
// Pre-flight 3D-RK4 Digital Twin & ASDS Placement Engine (asds_calculator.ks)
// ----------------------------------------------------------------------------
// Shares aero_atmo.ks physics with predictor_rk4.ks:
//   * Vehicle topology inspection (strips launch clamps, splits S1 & S2 mass)
//   * 3D spherical-Earth ascent RK4 (RealFuels pressure thrust + FAR drag/lift)
//   * Coupled descent RK4 across entry burn window [EB_FAR, EB_NEAR]
//   * S1 landing fuel margin, Max-Q, and S2 orbital delta-V envelope checks
// ============================================================================

// Inspect launchpad part tree: strip clamps and separate Stage 1 vs Stage 2+PL
FUNCTION inspect_vehicle_mass_breakdown {
    LOCAL tower_m IS 0.0.
    LOCAL pure_wet IS 0.0.
    LOCAL pure_dry IS 0.0.
    LOCAL s1_eng_dec IS -999.

    FOR pt IN SHIP:PARTS {
        IF pt:HASMODULE("ModuleTundraEngineSwitch") {
            SET s1_eng_dec TO pt:DECOUPLEDIN.
            BREAK.
        }
    }

    LOCAL s1_wet IS 0.0.
    LOCAL s1_dry IS 0.0.
    FOR pt IN SHIP:PARTS {
        IF pt:DRYMASS >= 100.0 OR pt:HASMODULE("LaunchClamp") OR pt:HASMODULE("ModuleLaunchClamp") {
            SET tower_m TO tower_m + pt:MASS.
        } ELSE {
            SET pure_wet TO pure_wet + pt:MASS.
            SET pure_dry TO pure_dry + pt:DRYMASS.
            IF s1_eng_dec <> -999 AND pt:DECOUPLEDIN = s1_eng_dec {
                SET s1_wet TO s1_wet + pt:MASS.
                SET s1_dry TO s1_dry + pt:DRYMASS.
            }
        }
    }

    LOCAL s1_detected IS TRUE.
    IF s1_wet < 200.0 OR s1_wet > pure_wet - 30.0 {
        SET s1_detected TO FALSE.
        LOCAL prof_s1_dry IS 22.2.
        IF DEFINED TUNDRA_F9_PROFILE { SET prof_s1_dry TO TUNDRA_F9_PROFILE["S1_DRY_MASS"]. }
        SET s1_dry TO prof_s1_dry.
        SET s1_wet TO MIN(pure_wet - 40.0, prof_s1_dry + 411.0).
    }

    LOCAL s1_prop IS MAX(0.0, s1_wet - s1_dry).
    LOCAL s2_wet IS MAX(1.0, pure_wet - s1_wet).
    LOCAL s2_dry IS MAX(1.0, pure_dry - s1_dry).

    RETURN LEXICON(
        "TOWER_MASS", tower_m,
        "PAD_PURE_MASS", pure_wet,
        "S1_WET_MASS", s1_wet,
        "S1_DRY_MASS", s1_dry,
        "S1_PROP_MASS", s1_prop,
        "S2_WET_MASS", s2_wet,
        "S2_DRY_MASS", s2_dry,
        "TOPOLOGY_OK", s1_detected
    ).
}

// 3D ground-track launch azimuth solver with Earth-rotation compensation
FUNCTION solve_launch_azimuth_3d {
    PARAMETER geo_pos, inc_deg, pe_alt, go_south.

    LOCAL lat IS geo_pos:LAT.
    LOCAL eff_inc IS MAX(ABS(lat), MIN(180.0 - ABS(lat), ABS(inc_deg))).
    LOCAL sin_az IS clamp(COS(eff_inc) / MAX(COS(lat), 0.001), -1.0, 1.0).
    LOCAL inertial_az IS ARCSIN(sin_az).
    IF go_south {
        SET inertial_az TO 180.0 - inertial_az.
    }

    LOCAL r_orb IS SHIP:BODY:RADIUS + pe_alt.
    LOCAL v_orb IS SQRT(SHIP:BODY:MU / r_orb).
    LOCAL v_rot IS (2.0 * CONSTANT:PI * SHIP:BODY:RADIUS / SHIP:BODY:ROTATIONPERIOD) * COS(lat).

    LOCAL v_east IS v_orb * SIN(inertial_az) - v_rot.
    LOCAL v_north IS v_orb * COS(inertial_az).
    LOCAL ground_az IS ARCTAN2(v_east, v_north).
    IF ground_az < 0.0 { SET ground_az TO ground_az + 360.0. }
    RETURN ground_az.
}

// Ascent RK4 acceleration evaluation (gravity + RF pressure thrust + FAR drag/lift)
FUNCTION rk4_ascent_accel {
    PARAMETER r_pos, v_vel, m_kg, sim_p, thrust_dir, rf_frac.

    LOCAL r_mag IS MAX(r_pos:MAG, 1.0).
    LOCAL h_agl IS r_mag - sim_p["R_BODY"].
    LOCAL grav_vec IS r_pos * (-sim_p["MU"] / (r_mag * r_mag * r_mag)).

    LOCAL p_atm IS SHIP:BODY:ATM:ALTITUDEPRESSURE(MAX(0.0, h_agl)).
    LOCAL f_full_n IS rf_pressure_thrust_n(sim_p["F_VAC_N"], sim_p["F_ASL_N"], p_atm).
    LOCAL thrust_vec IS thrust_dir * ((f_full_n * rf_frac) / MAX(m_kg, 1000.0)).

    LOCAL v_air IS v_vel - VCRS(sim_p["OMEGA"], r_pos).
    LOCAL v_air_mag IS v_air:MAG.
    LOCAL dens IS lookup_atmospheric_density(h_agl, sim_p["ATM_TOP"]).
    LOCAL drag_vec IS V(0, 0, 0).
    LOCAL lift_vec IS V(0, 0, 0).

    IF dens > 0.000001 AND v_air_mag > 0.1 {
        LOCAL a_snd IS lookup_rss_sound_speed(h_agl).
        LOCAL mach_est IS v_air_mag / a_snd.
        LOCAL q_s_over_m IS 0.5 * dens * v_air_mag * v_air_mag * sim_p["REF_AREA"] / MAX(m_kg, 1000.0).
        LOCAL v_air_unit IS v_air / v_air_mag.
        LOCAL sin_aoa_vec IS vxcl(v_air_unit, thrust_dir).
        LOCAL sin_aoa IS sin_aoa_vec:MAG.
        LOCAL cd_asc IS lookup_ascent_far_cd(mach_est, sin_aoa, sim_p["CN_ALPHA"]) * sim_p["DRAG_SCALE"].

        SET drag_vec TO v_air_unit * (-q_s_over_m * cd_asc).
        SET lift_vec TO sin_aoa_vec * (q_s_over_m * sim_p["CN_ALPHA"]).
    }

    RETURN grav_vec + thrust_vec + drag_vec + lift_vec.
}

// 3D-RK4 ascent integration from liftoff (t=0) to MECO_MASS cutoff
FUNCTION simulate_ascent_to_meco_rk4 {
    PARAMETER asc_cfg, veh, launch_az, drag_scale IS 1.0, cn_alpha IS 2.5.

    LOCAL prof IS asc_cfg["ASCENT_PROFILE"].
    LOCAL meco_mass_t IS asc_cfg["MECO_MASS"].
    IF meco_mass_t > veh["PAD_PURE_MASS"] AND veh["TOWER_MASS"] > 10.0 {
        SET meco_mass_t TO meco_mass_t - veh["TOWER_MASS"].
    }

    // Use calibrated 9-engine RF parameters directly (avoids multi-mode POSSIBLETHRUSTAT sum bug)
    LOCAL f_vac_kn IS 8227.08.
    LOCAL f_asl_kn IS 7632.00.
    LOCAL isp_vac IS 311.0.
    LOCAL min_throt IS 0.361.
    IF DEFINED TUNDRA_F9_PROFILE {
        LOCAL eng_all IS TUNDRA_F9_PROFILE["ENGINES"]["ALL"].
        SET f_vac_kn TO eng_all["MAX_THRUST_VAC"].
        SET f_asl_kn TO eng_all["MAX_THRUST_ASL"].
        SET isp_vac TO eng_all["ISP_VAC"].
        SET min_throt TO eng_all["MIN_THROTTLE"].
    }

    LOCAL far_ref_area IS 8.25.
    LOCAL f_vac_n IS f_vac_kn * 1000.0.
    LOCAL f_asl_n IS f_asl_kn * 1000.0.
    LOCAL mdot_full_kgs IS f_vac_n / (isp_vac * 9.80665).

    LOCAL sim_p IS LEXICON(
        "MU", SHIP:BODY:MU,
        "R_BODY", SHIP:BODY:RADIUS,
        "OMEGA", SHIP:BODY:ANGULARVEL,
        "ATM_TOP", 140000.0,
        "F_VAC_N", f_vac_n,
        "F_ASL_N", f_asl_n,
        "REF_AREA", far_ref_area,
        "DRAG_SCALE", drag_scale,
        "CN_ALPHA", cn_alpha
    ).

    LOCAL r_pos IS SHIP:POSITION - SHIP:BODY:POSITION.
    LOCAL u_pad_init IS r_pos:NORMALIZED.
    LOCAL v_vel IS VCRS(sim_p["OMEGA"], r_pos).
    LOCAL m_kg IS veh["PAD_PURE_MASS"] * 1000.0.
    LOCAL meco_kg IS MAX((veh["S2_WET_MASS"] + veh["S1_DRY_MASS"] + 2.0) * 1000.0, meco_mass_t * 1000.0).
    LOCAL min_meco_alt IS asc_cfg["MIN_MECO_ALT"].

    // Normalize planetary north pole before ENU projection
    LOCAL u_pole_n IS V(0, 1, 0).
    IF sim_p["OMEGA"]:MAG > 0.000000001 {
        SET u_pole_n TO (-sim_p["OMEGA"]):NORMALIZED.
    }

    LOCAL gear_off IS 43.5.
    IF DEFINED TUNDRA_F9_PROFILE { SET gear_off TO TUNDRA_F9_PROFILE["LANDING_GEAR_OFFSET"]. }
    LOCAL pad_radar_init IS MAX(0.0, ALT:RADAR - gear_off).
    LOCAL pad_elev IS SHIP:ALTITUDE - pad_radar_init.

    LOCAL pitch_start_alt IS prof["PITCH_START_ALT"].
    LOCAL pitch_end_alt IS prof["PITCH_END_ALT"].
    LOCAL target_pitch_end IS prof["TARGET_PITCH_END"].
    LOCAL pitch_exp IS prof["PITCH_CURVE_EXP"].
    LOCAL max_aoa IS 5.0.
    IF prof:HASKEY("MAX_AOA_DEG") { SET max_aoa TO prof["MAX_AOA_DEG"]. }

    LOCAL in_turn IS FALSE.
    LOCAL cmd_pitch_smooth IS 90.0.
    LOCAL act_pitch_deg IS 90.0.
    LOCAL t_asc IS 0.0.
    LOCAL dt_base IS 0.50.
    LOCAL step_n IS 0.
    LOCAL meco_hit IS FALSE.

    UNTIL meco_hit OR step_n >= 450 {
        LOCAL r_mag IS MAX(r_pos:MAG, 1.0).
        LOCAL u_up IS r_pos / r_mag.
        LOCAL h_agl IS r_mag - sim_p["R_BODY"].
        LOCAL sim_radar_alt IS h_agl - pad_elev.
        LOCAL v_air IS v_vel - VCRS(sim_p["OMEGA"], r_pos).
        LOCAL v_air_mag IS v_air:MAG.
        LOCAL v_radial IS v_air * u_up.
        LOCAL m_ton IS m_kg * 0.001.

        // Local orthonormal ENU basis at current position
        LOCAL u_east IS safe_normalize(VCRS(-u_pole_n, u_up), V(1, 0, 0)).
        LOCAL u_north IS safe_normalize(vxcl(u_up, u_pole_n), V(0, 1, 0)).
        LOCAL u_az IS (u_east * SIN(launch_az) + u_north * COS(launch_az)):NORMALIZED.

        LOCAL cmd_throt IS 1.0.
        IF NOT in_turn {
            SET cmd_pitch_smooth TO 90.0.
            IF sim_radar_alt >= pitch_start_alt AND v_radial > 45.0 {
                SET in_turn TO TRUE.
            }
        } ELSE {
            IF h_agl > min_meco_alt AND m_ton <= (meco_mass_t + 10.0) {
                IF m_ton <= (meco_mass_t + 2.5) {
                    SET cmd_throt TO 0.20.
                } ELSE {
                    SET cmd_throt TO 0.65.
                }
            } ELSE {
                LOCAL h_frac IS clamp((h_agl - pitch_start_alt) / MAX(1.0, pitch_end_alt - pitch_start_alt), 0.0, 1.0).
                LOCAL nom_pitch IS 90.0 - (90.0 - target_pitch_end) * (h_frac ^ pitch_exp).

                LOCAL dens_now IS lookup_atmospheric_density(h_agl, sim_p["ATM_TOP"]).
                LOCAL q_kpa IS 0.5 * dens_now * v_air_mag * v_air_mag * 0.001.
                IF q_kpa > 2.5 AND v_air_mag > 100.0 {
                    LOCAL srf_pitch IS 90.0 - VANG(u_up, v_air).
                    LOCAL dyn_aoa_lim IS clamp(max_aoa * (25.0 / MAX(q_kpa, 15.0)), 3.5, 8.0).
                    SET nom_pitch TO clamp(nom_pitch, srf_pitch - dyn_aoa_lim, srf_pitch + dyn_aoa_lim).
                }
                LOCAL cmd_alpha IS clamp(1.0 - (CONSTANT:E ^ (-dt_base / 0.20)), 0.05, 1.0).
                SET cmd_pitch_smooth TO cmd_pitch_smooth * (1.0 - cmd_alpha) + nom_pitch * cmd_alpha.
            }
        }

        LOCAL tvc_alpha IS clamp(1.0 - (CONSTANT:E ^ (-dt_base / 0.35)), 0.05, 1.0).
        SET act_pitch_deg TO act_pitch_deg * (1.0 - tvc_alpha) + cmd_pitch_smooth * tvc_alpha.
        LOCAL p_clamped IS clamp(act_pitch_deg, 0.0, 90.0).
        LOCAL thrust_dir IS (u_az * COS(p_clamped) + u_up * SIN(p_clamped)):NORMALIZED.

        LOCAL spool_frac IS clamp(0.25 + (t_asc / 0.60) * 0.75, 0.25, 1.0).
        LOCAL rf_frac IS rf_throttle_to_thrust_frac(cmd_throt, min_throt) * spool_frac.
        LOCAL mdot_cur IS mdot_full_kgs * rf_frac.
        LOCAL dt_step IS dt_base.

        IF h_agl >= min_meco_alt AND (m_kg - mdot_cur * dt_step) <= meco_kg {
            SET dt_step TO MAX(0.01, (m_kg - meco_kg) / MAX(mdot_cur, 1.0)).
            SET meco_hit TO TRUE.
        }

        LOCAL m_mid IS m_kg - mdot_cur * (dt_step * 0.5).
        LOCAL m_end IS m_kg - mdot_cur * dt_step.

        LOCAL k1r IS v_vel.
        LOCAL k1v IS rk4_ascent_accel(r_pos, v_vel, m_kg, sim_p, thrust_dir, rf_frac).
        LOCAL k2r IS v_vel + k1v * (dt_step * 0.5).
        LOCAL k2v IS rk4_ascent_accel(r_pos + k1r * (dt_step * 0.5), k2r, m_mid, sim_p, thrust_dir, rf_frac).
        LOCAL k3r IS v_vel + k2v * (dt_step * 0.5).
        LOCAL k3v IS rk4_ascent_accel(r_pos + k2r * (dt_step * 0.5), k3r, m_mid, sim_p, thrust_dir, rf_frac).
        LOCAL k4r IS v_vel + k3v * dt_step.
        LOCAL k4v IS rk4_ascent_accel(r_pos + k3r * dt_step, k4r, m_end, sim_p, thrust_dir, rf_frac).

        SET r_pos TO r_pos + (k1r + k2r * 2.0 + k3r * 2.0 + k4r) * (dt_step / 6.0).
        SET v_vel TO v_vel + (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (dt_step / 6.0).
        SET m_kg TO m_end.
        SET t_asc TO t_asc + dt_step.
        SET step_n TO step_n + 1.

        IF h_agl >= min_meco_alt AND m_kg <= meco_kg + 1.0 {
            SET meco_hit TO TRUE.
        }
    }

    LOCAL r_meco_mag IS MAX(r_pos:MAG, 1.0).
    LOCAL u_meco_up IS r_pos / r_meco_mag.
    LOCAL h_meco IS r_meco_mag - sim_p["R_BODY"].
    LOCAL v_meco_air_vec IS v_vel - VCRS(sim_p["OMEGA"], r_pos).
    LOCAL v_meco_air IS v_meco_air_vec:MAG.
    LOCAL vz_meco IS v_meco_air_vec * u_meco_up.
    LOCAL vh_meco IS vxcl(u_meco_up, v_meco_air_vec):MAG.
    LOCAL fpa_meco IS 90.0 - VANG(u_meco_up, v_meco_air_vec).

    LOCAL r_meco_fixed IS r_pos.
    IF sim_p["OMEGA"]:MAG > 0.000000001 {
        LOCAL spin_meco_deg IS sim_p["OMEGA"]:MAG * (180.0 / CONSTANT:PI) * t_asc * (-1.0).
        SET r_meco_fixed TO ANGLEAXIS(spin_meco_deg, sim_p["OMEGA"]:NORMALIZED) * r_pos.
    }
    LOCAL meco_dr_km IS (sim_p["R_BODY"] * (VANG(u_pad_init, r_meco_fixed:NORMALIZED) * CONSTANT:PI / 180.0)) / 1000.0.

    LOCAL m_burned_t IS veh["PAD_PURE_MASS"] - (m_kg * 0.001).
    LOCAL booster_sep_t IS MAX(veh["S1_DRY_MASS"] + 0.5, veh["S1_WET_MASS"] - m_burned_t).

    RETURN LEXICON(
        "OK", meco_hit,
        "R_MECO", r_pos,
        "V_MECO", v_vel,
        "T_MECO", t_asc,
        "H_MECO", h_meco,
        "V_MECO_ORB", v_vel:MAG,
        "V_MECO_AIR", v_meco_air,
        "VZ_MECO", vz_meco,
        "VH_MECO", vh_meco,
        "MECO_DR_KM", meco_dr_km,
        "FPA_MECO", fpa_meco,
        "MECO_MASS_T", m_kg * 0.001,
        "BOOSTER_SEP_T", booster_sep_t,
        "STEPS", step_n
    ).
}

// End-to-end digital twin: ascent RK4 + window-centered descent RK4 + envelope checks
FUNCTION run_preflight_asds_digital_twin {
    PARAMETER asc_cfg, rec_cfg, drag_scale IS 1.0, cn_alpha IS 2.5.

    LOCAL veh IS inspect_vehicle_mass_breakdown().
    LOCAL tgt_orbit IS asc_cfg["TARGET_ORBIT"].
    LOCAL prof IS asc_cfg["ASCENT_PROFILE"].

    LOCAL is_fixed_lan IS (tgt_orbit:HASKEY("LAN_MODE") AND tgt_orbit["LAN_MODE"] = "FIXED").
    LOCAL tgt_lan IS 0.0.
    IF tgt_orbit:HASKEY("LAN") { SET tgt_lan TO tgt_orbit["LAN"]. }
    LOCAL lan_lead IS 150.0.
    IF tgt_orbit:HASKEY("LAN_LEAD_TIME") { SET lan_lead TO tgt_orbit["LAN_LEAD_TIME"]. }

    LOCAL go_south IS resolve_launch_south_branch(
        SHIP:GEOPOSITION,
        tgt_orbit["INCLINATION"],
        prof["LAUNCH_SOUTH"],
        tgt_lan,
        lan_lead,
        is_fixed_lan
    ).

    LOCAL launch_az IS prof["MANUAL_AZIMUTH"].
    IF prof["USE_TARGET_AZIMUTH"] {
        SET launch_az TO solve_launch_azimuth_3d(
            SHIP:GEOPOSITION,
            tgt_orbit["INCLINATION"],
            tgt_orbit["PERIAPSIS"],
            go_south
        ).
    }

    // Stage A: 3D-RK4 ascent to MECO
    LOCAL asc_sim IS simulate_ascent_to_meco_rk4(asc_cfg, veh, launch_az, drag_scale, cn_alpha).

    // Stage B: Coupled descent RK4 centered inside reachable entry burn window [EB_FAR, EB_NEAR]
    LOCAL desc_pred_cfg IS rec_cfg["PREDICTOR"]:COPY.
    SET desc_pred_cfg["DT"] TO 2.0.
    SET desc_pred_cfg["MAX_STEPS"] TO 420.

    LOCAL sim_guide_cfg IS rec_cfg["GUIDANCE"]:COPY.
    LOCAL eb_max_safe IS 1250.0.
    LOCAL eb_min_spd IS sim_guide_cfg["ENTRY_BURN_END_SPEED"].
    LOCAL eb_min_prop IS 4.6.
    LOCAL coast_entry_alt IS sim_guide_cfg["COAST_ENTRY_ALT"].
    IF asc_cfg["RECOVERY_MODE"] <> "RTLS" AND rec_cfg:HASKEY("ASDS_PROFILE") {
        LOCAL ap IS rec_cfg["ASDS_PROFILE"].
        IF ap:HASKEY("DECK_ELEVATION")        { SET desc_pred_cfg["MIN_ALT"] TO MAX(desc_pred_cfg["MIN_ALT"], ap["DECK_ELEVATION"]). }
        IF ap:HASKEY("EB_MAX_SAFE_SPEED")     { SET eb_max_safe TO ap["EB_MAX_SAFE_SPEED"]. }
        IF ap:HASKEY("EB_END_SPEED")          { SET eb_min_spd TO ap["EB_END_SPEED"]. }
        IF ap:HASKEY("EB_MIN_LANDING_PROP_T") { SET eb_min_prop TO ap["EB_MIN_LANDING_PROP_T"]. }
        IF ap:HASKEY("COAST_ENTRY_ALT")       { SET coast_entry_alt TO ap["COAST_ENTRY_ALT"]. }
    } ELSE IF asc_cfg["RECOVERY_MODE"] = "RTLS" AND rec_cfg:HASKEY("RTLS_PROFILE") {
        LOCAL rp IS rec_cfg["RTLS_PROFILE"].
        IF rp:HASKEY("EB_END_SPEED")          { SET eb_min_spd TO rp["EB_END_SPEED"]. }
        IF rp:HASKEY("EB_MIN_LANDING_PROP_T") { SET eb_min_prop TO rp["EB_MIN_LANDING_PROP_T"]. }
        IF rp:HASKEY("COAST_ENTRY_ALT")       { SET coast_entry_alt TO rp["COAST_ENTRY_ALT"]. }
    }
    SET sim_guide_cfg["COAST_ENTRY_ALT"] TO coast_entry_alt.
    SET sim_guide_cfg["EB_MIN_LANDING_PROP_T"] TO eb_min_prop.

    LOCAL eb_window_km IS 0.0.
    LOCAL eb_nom_spd IS eb_min_spd.
    LOCAL eb_near_alt_km IS 36.0.
    LOCAL eb_near_spd IS eb_min_spd.
    LOCAL eb_far_spd IS eb_max_safe.
    LOCAL desc_sim IS LEXICON().

    IF asc_cfg["RECOVERY_MODE"] <> "RTLS" {
        LOCAL far_guide IS sim_guide_cfg:COPY.
        SET far_guide["ENTRY_BURN_END_SPEED"] TO eb_max_safe.
        LOCAL desc_far IS predict_impact_state(
            make_prediction_params(desc_pred_cfg, TRUE, far_guide, asc_sim["BOOSTER_SEP_T"] * 1000.0, TRUE, veh["S1_DRY_MASS"] * 1000.0),
            asc_sim["R_MECO"], asc_sim["V_MECO"], asc_sim["T_MECO"]
        ).

        LOCAL near_guide IS sim_guide_cfg:COPY.
        SET near_guide["ENTRY_BURN_END_SPEED"] TO eb_min_spd.
        LOCAL desc_near IS predict_impact_state(
            make_prediction_params(desc_pred_cfg, TRUE, near_guide, asc_sim["BOOSTER_SEP_T"] * 1000.0, TRUE, veh["S1_DRY_MASS"] * 1000.0),
            asc_sim["R_MECO"], asc_sim["V_MECO"], asc_sim["T_MECO"]
        ).

        SET eb_window_km TO (SHIP:BODY:RADIUS * (VANG(desc_far["ASDS_FIXED"]:NORMALIZED, desc_near["ASDS_FIXED"]:NORMALIZED) * CONSTANT:PI / 180.0)) / 1000.0.
        IF desc_far:HASKEY("EB_END_SPD") AND desc_far["EB_END_SPD"] > 10.0 { SET eb_far_spd TO desc_far["EB_END_SPD"]. }
        IF desc_near:HASKEY("EB_END_SPD") AND desc_near["EB_END_SPD"] > 10.0 { SET eb_near_spd TO desc_near["EB_END_SPD"]. }
        IF desc_near:HASKEY("EB_END_ALT") { SET eb_near_alt_km TO desc_near["EB_END_ALT"] / 1000.0. }
        SET eb_nom_spd TO 0.5 * (eb_far_spd + eb_near_spd).
        SET sim_guide_cfg["ENTRY_BURN_END_SPEED"] TO eb_nom_spd.

        SET desc_sim TO predict_impact_state(
            make_prediction_params(desc_pred_cfg, TRUE, sim_guide_cfg, asc_sim["BOOSTER_SEP_T"] * 1000.0, TRUE, veh["S1_DRY_MASS"] * 1000.0),
            asc_sim["R_MECO"], asc_sim["V_MECO"], asc_sim["T_MECO"]
        ).
    } ELSE {
        SET sim_guide_cfg["ENTRY_BURN_END_SPEED"] TO eb_min_spd.
        SET desc_sim TO predict_impact_state(
            make_prediction_params(desc_pred_cfg, TRUE, sim_guide_cfg, asc_sim["BOOSTER_SEP_T"] * 1000.0, TRUE, veh["S1_DRY_MASS"] * 1000.0),
            asc_sim["R_MECO"], asc_sim["V_MECO"], asc_sim["T_MECO"]
        ).
        IF desc_sim:HASKEY("EB_END_ALT") { SET eb_near_alt_km TO desc_sim["EB_END_ALT"] / 1000.0. }
        IF desc_sim:HASKEY("EB_END_SPD") { SET eb_near_spd TO desc_sim["EB_END_SPD"]. }
    }

    LOCAL u_pad IS (SHIP:POSITION - SHIP:BODY:POSITION):NORMALIZED.
    LOCAL u_asds IS desc_sim["ASDS_FIXED"]:NORMALIZED.
    LOCAL downrange_km IS (SHIP:BODY:RADIUS * (VANG(u_pad, u_asds) * CONSTANT:PI / 180.0)) / 1000.0.

    // Stage C: Analytic Stage 1 hoverslam propellant margin check
    LOCAL f1_asl_kn IS 848.0.
    LOCAL isp1_asl IS 288.5.
    LOCAL isp_s2_vac IS 348.0.
    IF DEFINED TUNDRA_F9_PROFILE {
        SET f1_asl_kn TO TUNDRA_F9_PROFILE["ENGINES"]["CENTER"]["MAX_THRUST_ASL"].
        SET isp1_asl TO TUNDRA_F9_PROFILE["ENGINES"]["CENTER"]["ISP_ASL"].
        SET isp_s2_vac TO TUNDRA_F9_PROFILE["ENGINES"]["S2_VAC"]["ISP_VAC"].
    }

    LOCAL m_post_eb_t IS desc_sim["M_POST_EB_KG"] * 0.001.
    LOCAL eb_fuel_t IS MAX(0.0, asc_sim["BOOSTER_SEP_T"] - m_post_eb_t).
    LOCAL v3 IS MAX(50.0, desc_sim["V_3KM"]).
    LOCAL vz3_abs IS MAX(30.0, ABS(desc_sim["VZ_3KM"])).
    LOCAL grav0 IS 9.80665.
    LOCAL a1_avail IS f1_asl_kn / MAX(m_post_eb_t, 1.0).
    LOCAL a_net_land IS MAX(1.5, a1_avail * 0.78 - grav0).
    LOCAL t_land_est IS vz3_abs / a_net_land.
    LOCAL dv_land_est IS v3 + grav0 * t_land_est * (vz3_abs / v3).
    LOCAL m_td_t IS m_post_eb_t * (CONSTANT:E ^ (-dv_land_est / (isp1_asl * grav0))).
    LOCAL land_fuel_t IS MAX(0.0, m_post_eb_t - m_td_t).
    LOCAL fuel_margin_t IS m_td_t - veh["S1_DRY_MASS"].

    // Stage D: Stage 2 orbital insertion delta-V check
    LOCAL r_body IS SHIP:BODY:RADIUS.
    LOCAL grav_mu IS SHIP:BODY:MU.
    LOCAL r_pe IS r_body + tgt_orbit["PERIAPSIS"].
    LOCAL a_tgt IS r_body + (tgt_orbit["PERIAPSIS"] + MAX(tgt_orbit["PERIAPSIS"], tgt_orbit["APOAPSIS"])) / 2.0.
    LOCAL v_tgt_orb IS SQRT(grav_mu * (2.0 / r_pe - 1.0 / a_tgt)).
    LOCAL r_meco_m IS r_body + asc_sim["H_MECO"].
    LOCAL dv_pot_sq IS MAX(0.0, 2.0 * grav_mu * (1.0 / r_meco_m - 1.0 / r_pe)).
    LOCAL s2_dv_req IS (SQRT(v_tgt_orb * v_tgt_orb + dv_pot_sq) - asc_sim["V_MECO_ORB"]) * 1.035.
    LOCAL s2_dv_avail IS isp_s2_vac * grav0 * LN(veh["S2_WET_MASS"] / MAX(veh["S2_DRY_MASS"], 0.1)).
    LOCAL s2_dv_margin IS s2_dv_avail - s2_dv_req.

    RETURN LEXICON(
        "VEH", veh,
        "GO_SOUTH", go_south,
        "AZIMUTH_DEG", launch_az,
        "ASC", asc_sim,
        "DESC", desc_sim,
        "DOWNRANGE_KM", downrange_km,
        "EB_WINDOW_KM", eb_window_km,
        "EB_NOM_SPD", eb_nom_spd,
        "EB_NEAR_ALT_KM", eb_near_alt_km,
        "EB_NEAR_SPD", eb_near_spd,
        "EB_FAR_SPD", eb_far_spd,
        "EB_FUEL_T", eb_fuel_t,
        "LAND_FUEL_T", land_fuel_t,
        "DV_LAND_EST", dv_land_est,
        "FUEL_MARGIN_T", fuel_margin_t,
        "S2_DV_REQ", s2_dv_req,
        "S2_DV_AVAIL", s2_dv_avail,
        "S2_DV_MARGIN", s2_dv_margin,
        "FUEL_OK", (fuel_margin_t >= 4.0),
        "AERO_OK", (desc_sim["MAX_Q_KPA"] <= 90.0),
        "S2_OK", (s2_dv_margin >= 50.0)
    ).
}
