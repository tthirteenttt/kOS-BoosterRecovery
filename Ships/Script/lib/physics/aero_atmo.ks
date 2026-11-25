// ============================================================================
// Single-Source Physics Kernel (aero_atmo.ks) v1.0
// ----------------------------------------------------------------------------
// Centralizes RSS atmospheric density, speed of sound, C1-smooth aerodynamics,
// RealFuels thrust/throttle mapping, and pure-function Hoverslam kinematics.
// Shared across asds_calculator.ks, predictor_rk4.ks, and hoverslam_guide.ks.
// ============================================================================

GLOBAL RSS_RHO_LUT IS LIST(
    1.1890,  //  0 km
    0.9750,  //  2 km
    0.7900,  //  4 km
    0.6380,  //  6 km
    0.5130,  //  8 km
    0.4090,  // 10 km
    0.3190,  // 12 km
    0.2470,  // 14 km
    0.1810,  // 16 km
    0.1340,  // 18 km
    0.0950,  // 20 km
    0.0675,  // 22 km
    0.0485,  // 24 km
    0.0348,  // 26 km
    0.0252,  // 28 km
    0.0188,  // 30 km
    0.0135,  // 32 km
    0.0098,  // 34 km
    0.0069,  // 36 km
    0.0054,  // 38 km
    0.0043,  // 40 km
    0.0033,  // 42 km
    0.0025,  // 44 km
    0.0019,  // 46 km
    0.0014,  // 48 km
    0.0011,  // 50 km
    0.00082, // 52 km
    0.00063, // 54 km
    0.00048, // 56 km
    0.00037, // 58 km
    0.00028, // 60 km
    0.00021, // 62 km
    0.00016, // 64 km
    0.00012, // 66 km
    0.00009, // 68 km
    0.00007  // 70 km
).

FUNCTION lookup_atmospheric_density {
    PARAMETER h_agl, atm_top IS 140000.0.

    IF h_agl <= 0.0 {
        RETURN RSS_RHO_LUT[0].
    }
    IF h_agl >= atm_top {
        RETURN 0.0.
    }
    IF h_agl < 70000.0 {
        LOCAL h_scaled IS h_agl * 0.0005.
        LOCAL idx IS FLOOR(h_scaled).
        LOCAL frac IS h_scaled - idx.
        LOCAL r0 IS RSS_RHO_LUT[idx].
        RETURN r0 + (RSS_RHO_LUT[idx + 1] - r0) * frac.
    }
    RETURN 0.00007 * (CONSTANT:E ^ (-(h_agl - 70000.0) / 6500.0)).
}

FUNCTION lookup_rss_sound_speed {
    PARAMETER h_agl.

    IF h_agl <= 0.0 { RETURN 342.0. }
    IF h_agl < 6000.0 { RETURN 342.0 - (h_agl / 6000.0) * 30.0. }
    IF h_agl < 16000.0 { RETURN 312.0 - ((h_agl - 6000.0) / 10000.0) * 23.0. }
    IF h_agl < 32000.0 { RETURN 289.0 + ((h_agl - 16000.0) / 16000.0) * 19.0. }
    IF h_agl < 51000.0 { RETURN 308.0 + ((h_agl - 32000.0) / 19000.0) * 22.0. }
    IF h_agl < 70000.0 { RETURN 330.0 - ((h_agl - 51000.0) / 19000.0) * 34.0. }
    RETURN 295.0.
}

FUNCTION compute_booster_cd {
    PARAMETER mach_val, base_cd IS 3.12, sin_aoa IS 0.0, cn_alpha IS 3.9.

    LOCAL cd_peak IS base_cd * 1.13.
    LOCAL cd0 IS base_cd.
    IF mach_val <= 0.68 {
        SET cd0 TO 1.11.
    } ELSE IF mach_val < 1.05 {
        SET cd0 TO 1.11 + (cd_peak - 1.11) * hermite_step((mach_val - 0.68) / 0.37).
    } ELSE IF mach_val < 1.30 {
        SET cd0 TO cd_peak.
    } ELSE IF mach_val < 2.10 {
        SET cd0 TO cd_peak - (cd_peak - base_cd) * hermite_step((mach_val - 1.30) / 0.80).
    } ELSE {
        SET cd0 TO base_cd.
    }
    RETURN cd0 + cn_alpha * sin_aoa * sin_aoa.
}

FUNCTION lookup_ascent_far_cd {
    PARAMETER mach_val, sin_aoa IS 0.0, cn_alpha IS 2.5.

    LOCAL cd0 IS 1.980.
    IF mach_val <= 0.54 {
        SET cd0 TO 0.042.
    } ELSE IF mach_val < 0.86 {
        SET cd0 TO 0.042 + ((mach_val - 0.54) / 0.32) * (1.268 - 0.042).
    } ELSE IF mach_val < 1.36 {
        SET cd0 TO 1.268 + ((mach_val - 0.86) / 0.50) * (1.772 - 1.268).
    } ELSE IF mach_val < 2.32 {
        SET cd0 TO 1.772 + ((mach_val - 1.36) / 0.96) * (1.854 - 1.772).
    } ELSE IF mach_val < 5.13 {
        SET cd0 TO 1.854 + ((mach_val - 2.32) / 2.81) * (1.996 - 1.854).
    }
    RETURN cd0 + cn_alpha * sin_aoa * sin_aoa.
}

FUNCTION rf_throttle_to_thrust_frac {
    PARAMETER cmd_throt, min_throt.
    RETURN min_throt + (1.0 - min_throt) * clamp(cmd_throt, 0.0, 1.0).
}

FUNCTION rf_thrust_frac_to_cmd {
    PARAMETER thrust_frac, min_throt, max_throt IS 0.98.
    RETURN clamp((thrust_frac - min_throt) / MAX(1.0 - min_throt, 0.01), 0.01, max_throt).
}

FUNCTION rf_pressure_thrust_n {
    PARAMETER f_vac_n, f_asl_n, p_atm.
    RETURN f_vac_n - (f_vac_n - f_asl_n) * clamp(p_atm, 0.0, 1.0).
}

FUNCTION solve_hoverslam_ignition_alt {
    PARAMETER vert_speed, horiz_speed, max_accel, grav0, margin_dist, spool_lead_s IS 2.0.

    LOCAL eff_accel IS MAX(1.5, max_accel * 0.81 - grav0).
    LOCAL spd_sq IS vert_speed * vert_speed + 0.12 * (horiz_speed * horiz_speed).
    RETURN spd_sq / (2.0 * eff_accel) + ABS(vert_speed) * spool_lead_s + margin_dist.
}

FUNCTION solve_hoverslam_req_accel_z {
    PARAMETER radar_alt, vert_speed, target_td_vel, grav0, flare_alt IS 0.6.

    LOCAL eff_alt IS MAX(0.5, radar_alt - flare_alt).
    LOCAL kin_decel IS MAX(0.0, (vert_speed * vert_speed - target_td_vel * target_td_vel) / (2.0 * eff_alt)).
    RETURN grav0 + kin_decel.
}
