// ============================================================================
// Powered Explicit Guidance (UPEG) for Upper-Stage Insertion (upeg_guide.ks)
// ----------------------------------------------------------------------------
// Supports circular, elliptical/GTO, polar, and retrograde SSO orbits under
// both IGNORE LAN (Clairaut spherical plane projection) and FIXED LAN
// (equinox-anchored inertial plane + ZEM-ZEV cross-track nulling).
// ============================================================================

FUNCTION is_lan_ignored {
    PARAMETER target_orbit.

    IF target_orbit:HASKEY("LAN_MODE") {
        IF target_orbit["LAN_MODE"] = "IGNORE" {
            RETURN TRUE.
        }
    }
    IF target_orbit:HASKEY("IGNORE_LAN") {
        IF target_orbit["IGNORE_LAN"] {
            RETURN TRUE.
        }
    }
    RETURN FALSE.
}

FUNCTION current_plane_normal {
    LOCAL r_vec IS SHIP:POSITION - SHIP:BODY:POSITION.
    LOCAL v_vec IS SHIP:VELOCITY:ORBIT.
    LOCAL h_vec IS VCRS(r_vec, v_vec).

    IF h_vec:MAG < 0.001 {
        SET h_vec TO VCRS(r_vec, SHIP:NORTH:VECTOR).
    }
    IF h_vec:MAG < 0.001 {
        SET h_vec TO V(0, 1, 0).
    }
    RETURN h_vec:NORMALIZED.
}

// Clairaut spherical trigonometry: target plane normal through current position at inc_tgt
FUNCTION compute_clairaut_plane_normal {
    PARAMETER r_unit, v_vec, inc_tgt, h_fallback.

    LOCAL lat IS SHIP:GEOPOSITION:LAT.
    LOCAL sin_az IS clamp(COS(inc_tgt) / MAX(COS(lat), 0.001), -1.0, 1.0).
    LOCAL az_iner IS ARCSIN(sin_az).

    // Match ascending (northbound) or descending (southbound) branch
    IF (v_vec * HEADING(0.0, 0.0):VECTOR) < 0.0 {
        SET az_iner TO 180.0 - az_iner.
    }
    IF az_iner < 0.0 {
        SET az_iner TO az_iner + 360.0.
    }

    LOCAL horiz_tgt_dir IS HEADING(az_iner, 0.0):VECTOR.
    LOCAL h_inc IS VCRS(r_unit, horiz_tgt_dir).
    IF h_inc:MAG > 0.001 {
        SET h_inc TO h_inc:NORMALIZED.
        IF (h_inc * h_fallback) < 0.0 {
            SET h_inc TO -h_inc.
        }
        // Allow up to 25 deg plane gap at MECO (accounts for polar/SSO rotation offset)
        IF VANG(h_fallback, h_inc) <= 25.0 {
            RETURN h_inc.
        }
    }
    RETURN h_fallback.
}

// Inertial target plane normal from (inc_tgt, lan_tgt) referenced to SOLARPRIMEVECTOR
FUNCTION compute_fixed_plane_normal {
    PARAMETER inc_tgt, lan_tgt.

    LOCAL north_pole IS -SHIP:BODY:ANGULARVEL:NORMALIZED.
    LOCAL x_axis IS vxcl(north_pole, SOLARPRIMEVECTOR):NORMALIZED.
    LOCAL z_axis IS VCRS(x_axis, north_pole):NORMALIZED.
    LOCAL e_node IS (-SIN(lan_tgt) * x_axis + COS(lan_tgt) * z_axis):NORMALIZED.
    RETURN (-COS(inc_tgt) * north_pole + SIN(inc_tgt) * e_node):NORMALIZED.
}

FUNCTION build_target_plane_normal {
    PARAMETER target_orbit.

    LOCAL h_cur IS current_plane_normal().
    LOCAL r_unit IS (SHIP:POSITION - SHIP:BODY:POSITION):NORMALIZED.
    LOCAL v_vec IS SHIP:VELOCITY:ORBIT.

    IF is_lan_ignored(target_orbit) {
        IF target_orbit:HASKEY("INCLINATION") {
            RETURN compute_clairaut_plane_normal(
                r_unit, v_vec, ABS(target_orbit["INCLINATION"]), h_cur
            ).
        }
        RETURN h_cur.
    }

    LOCAL lan_tgt IS 0.0.
    IF target_orbit:HASKEY("LAN") {
        SET lan_tgt TO target_orbit["LAN"].
    }
    LOCAL d_lan IS lan_tgt - SHIP:OBT:LAN.
    LOCAL guard IS 0.
    UNTIL (d_lan <= 180.0 AND d_lan >= -180.0) OR guard >= 20 {
        IF d_lan > 180.0 { SET d_lan TO d_lan - 360.0. }
        IF d_lan < -180.0 { SET d_lan TO d_lan + 360.0. }
        SET guard TO guard + 1.
    }

    LOCAL spin_axis IS SHIP:BODY:ANGULARVEL.
    IF spin_axis:MAG < 0.0000001 {
        RETURN h_cur.
    }
    SET spin_axis TO spin_axis:NORMALIZED.

    LOCAL c_lan IS COS(d_lan).
    LOCAL s_lan IS SIN(d_lan).
    LOCAL h_tgt IS h_cur * c_lan
                 + VCRS(spin_axis, h_cur) * s_lan
                 + spin_axis * (spin_axis * h_cur) * (1.0 - c_lan).

    IF h_tgt:MAG < 0.001 {
        RETURN h_cur.
    }
    RETURN h_tgt:NORMALIZED.
}

FUNCTION init_upeg {
    PARAMETER target_orbit, max_burn_time IS 600.0.

    LOCAL grav_mu IS SHIP:BODY:MU.
    LOCAL r_body IS SHIP:BODY:RADIUS.
    LOCAL pe_alt IS target_orbit["PERIAPSIS"].
    LOCAL ap_alt IS MAX(pe_alt, target_orbit["APOAPSIS"]).
    LOCAL inc_tgt IS SHIP:OBT:INCLINATION.
    IF target_orbit:HASKEY("INCLINATION") {
        SET inc_tgt TO ABS(target_orbit["INCLINATION"]).
    }
    LOCAL min_lat_inc IS ABS(SHIP:GEOPOSITION:LAT).
    IF NOT is_lan_ignored(target_orbit) {
        IF inc_tgt < min_lat_inc OR inc_tgt > (180.0 - min_lat_inc) {
            LOCAL clamped_inc IS MAX(min_lat_inc, MIN(180.0 - min_lat_inc, inc_tgt)).
            log_warn("UPEG", "Target Inc " + ROUND(inc_tgt, 2) + " deg unreachable from lat " +
                             ROUND(SHIP:GEOPOSITION:LAT, 2) + " deg; clamped to " + ROUND(clamped_inc, 2) + " deg.").
            SET inc_tgt TO clamped_inc.
        }
    }

    LOCAL r_tgt IS r_body + pe_alt.
    LOCAL a_tgt IS r_body + (pe_alt + ap_alt) / 2.0.
    LOCAL v_tgt IS SQRT(grav_mu * (2.0 / r_tgt - 1.0 / a_tgt)).
    LOCAL h_unit IS build_target_plane_normal(target_orbit).

    LOCAL lan_tgt IS 0.0.
    IF target_orbit:HASKEY("LAN") {
        SET lan_tgt TO target_orbit["LAN"].
    }

    RETURN LEXICON(
        "r_tgt", r_tgt,
        "a_tgt", a_tgt,
        "v_tgt", v_tgt,
        "h_unit", h_unit,
        "target_inc", inc_tgt,
        "ignore_lan", is_lan_ignored(target_orbit),
        "target_pe", pe_alt,
        "target_apo", ap_alt,
        "target_lan", lan_tgt,
        "max_burn_time", max_burn_time,
        "elapsed", 0.0,
        "t_go", 320.0,
        "prev_steer", SHIP:FACING:VECTOR,
        "last_u_r", 0.30,
        "cutoff", FALSE,
        "cutoff_reason", ""
    ).
}

FUNCTION step_upeg_guidance {
    PARAMETER upeg_state, dt.

    SET upeg_state["elapsed"] TO upeg_state["elapsed"] + MAX(0.0, dt).

    LOCAL r_vec IS SHIP:POSITION - SHIP:BODY:POSITION.
    LOCAL v_vec IS SHIP:VELOCITY:ORBIT.
    LOCAL r_mag IS MAX(r_vec:MAG, 1.0).
    LOCAL r_unit IS r_vec:NORMALIZED.
    LOCAL grav_mu IS SHIP:BODY:MU.

    // 1. Target orbital plane normal and local orthonormal frame (r_unit, downrange_unit, h_horiz)
    LOCAL h_unit IS upeg_state["h_unit"].
    LOCAL inc_tgt IS upeg_state["target_inc"].
    LOCAL max_lat IS MIN(inc_tgt, 180.0 - inc_tgt).
    LOCAL y_cross IS 0.0.

    IF upeg_state["ignore_lan"] {
        IF ABS(SHIP:GEOPOSITION:LAT) < (max_lat - 2.0) {
            SET h_unit TO compute_clairaut_plane_normal(r_unit, v_vec, inc_tgt, h_unit).
            SET upeg_state["h_unit"] TO h_unit.
        } ELSE {
            SET h_unit TO safe_normalize(vxcl(r_unit, h_unit), current_plane_normal()).
            SET upeg_state["h_unit"] TO h_unit.
        }
    } ELSE {
        // Refresh equinox-anchored inertial plane every tick (immune to KSP 100 km frame switch)
        SET h_unit TO compute_fixed_plane_normal(inc_tgt, upeg_state["target_lan"]).
        SET upeg_state["h_unit"] TO h_unit.
        SET y_cross TO r_vec * h_unit.
    }

    LOCAL downrange_unit IS VCRS(h_unit, r_unit).
    IF downrange_unit:MAG < 0.001 {
        SET downrange_unit TO vxcl(r_unit, v_vec).
    }
    SET downrange_unit TO safe_normalize(downrange_unit, SHIP:PROGRADE:VECTOR).
    IF upeg_state["ignore_lan"] AND (downrange_unit * v_vec) < 0.0 {
        SET downrange_unit TO -downrange_unit.
    }
    LOCAL h_horiz IS safe_normalize(VCRS(r_unit, downrange_unit), h_unit).

    // 2. Spherical velocity components
    LOCAL v_radial IS v_vec * r_unit.
    LOCAL v_theta IS MAX(1.0, v_vec * downrange_unit).
    LOCAL v_cross IS v_vec * h_unit.

    // 3. Live thrust acceleration a_0 and exhaust velocity v_e
    LOCAL s2_thrust IS SHIP:THRUST.
    IF s2_thrust < 50.0 {
        SET s2_thrust TO SHIP:AVAILABLETHRUST.
    }
    IF s2_thrust < 50.0 {
        SET s2_thrust TO 981.0.
        IF DEFINED TUNDRA_F9_PROFILE AND TUNDRA_F9_PROFILE["ENGINES"]:HASKEY("S2_VAC") {
            SET s2_thrust TO TUNDRA_F9_PROFILE["ENGINES"]["S2_VAC"]["MAX_THRUST_VAC"].
        }
    }
    LOCAL a_0 IS s2_thrust / MAX(SHIP:MASS, 0.1).
    LOCAL v_e IS 348.0 * 9.80665.
    LOCAL tau IS MAX(8.0, v_e / MAX(a_0, 0.1)).

    // 4. Angular-momentum-corrected tangential velocity deficit and time-to-go
    LOCAL v_tgt IS upeg_state["v_tgt"].
    LOCAL r_tgt IS upeg_state["r_tgt"].
    LOCAL dv_coriolis IS 0.5 * (v_tgt + v_theta) * (r_tgt - r_mag) / r_tgt.
    LOCAL dv_theta IS MAX(0.0, (v_tgt - v_theta) + dv_coriolis).
    LOCAL pitch_eff IS SQRT(MAX(0.55, 1.0 - 0.5 * upeg_state["last_u_r"] * upeg_state["last_u_r"])).
    LOCAL b0_req IS dv_theta / pitch_eff.
    LOCAL t_go IS clamp(tau * (1.0 - (CONSTANT:E ^ (-b0_req / v_e))), 0.05, tau * 0.96).
    SET upeg_state["t_go"] TO t_go.

    // 5. Simpson 1/3 gravity-centrifugal quadrature + NASA PEG (A, B) linear-tangent law
    LOCAL g_eff_0 IS (v_theta * v_theta) / r_mag - grav_mu / (r_mag * r_mag).
    LOCAL g_eff_T IS (v_tgt * v_tgt) / r_tgt - grav_mu / (r_tgt * r_tgt).
    LOCAL u_r IS upeg_state["last_u_r"].

    IF t_go > 8.0 {
        LOCAL b0 IS -v_e * LN(1.0 - t_go / tau).
        LOCAL b1 IS b0 * tau - v_e * t_go.
        LOCAL b2 IS tau * b1 - 0.5 * v_e * t_go * t_go.
        LOCAL c0 IS b0 * t_go - b1.
        LOCAL c1 IS t_go * b1 - b2.

        LOCAL b0_mid IS -v_e * LN(1.0 - (0.5 * t_go) / tau).
        LOCAL v_theta_mid IS MIN(v_tgt, v_theta + b0_mid * pitch_eff).
        LOCAL r_mid IS 0.5 * (r_mag + r_tgt) + 0.125 * v_radial * t_go.
        LOCAL g_eff_mid IS (v_theta_mid * v_theta_mid) / r_mid - grav_mu / (r_mid * r_mid).

        LOCAL dv_grav IS (g_eff_0 + 4.0 * g_eff_mid + g_eff_T) * (t_go / 6.0).
        LOCAL dr_grav IS (g_eff_0 + 2.0 * g_eff_mid) * (t_go * t_go / 6.0).

        LOCAL dv_r_req IS 0.0 - v_radial - dv_grav.
        LOCAL dr_req IS (r_tgt - r_mag) - v_radial * t_go - dr_grav.

        LOCAL det_pos IS MAX(1.0, b1 * c0 - b0 * c1).
        LOCAL coeff_A IS (b1 * dr_req - c1 * dv_r_req) / det_pos.
        LOCAL coeff_B IS (c0 * dv_r_req - b0 * dr_req) / det_pos.

        LOCAL t_lead IS MIN(1.8, t_go * 0.25).
        SET u_r TO clamp(coeff_A + coeff_B * t_lead, -0.45, 0.75).
        SET upeg_state["last_u_r"] TO u_r.
    } ELSE {
        LOCAL r_err_term IS clamp((r_tgt - r_mag) * 0.015, -3.0, 3.0).
        LOCAL target_vr IS r_err_term * clamp((t_go - 2.5) / 5.5, 0.0, 1.0).
        LOCAL a_r_term IS ((target_vr - v_radial) / MAX(t_go * 0.45, 0.5)) - g_eff_0.
        SET u_r TO clamp(a_r_term / MAX(a_0, 1.0), -0.35, 0.40).
    }

    // 6. Cross-track control: velocity nulling (IGNORE) or ZEM-ZEV plane capture (FIXED)
    LOCAL a_cross_cmd IS 0.0.
    IF upeg_state["ignore_lan"] {
        LOCAL t_cross IS MAX(t_go * 0.55, 1.2).
        SET a_cross_cmd TO -v_cross / t_cross.
    } ELSE {
        LOCAL g_cross IS -(grav_mu / (r_mag * r_mag * r_mag)) * y_cross.
        IF t_go > 15.0 {
            SET a_cross_cmd TO (-6.0 * y_cross / (t_go * t_go)) - (4.0 * v_cross / t_go) - g_cross.
        } ELSE {
            LOCAL pos_fade IS clamp((t_go - 6.0) / 9.0, 0.0, 1.0).
            SET a_cross_cmd TO ((-6.0 * y_cross / 225.0) * pos_fade) - (2.2 * v_cross / MAX(t_go, 1.2)) - g_cross.
        }
    }
    LOCAL u_h IS clamp(a_cross_cmd / MAX(a_0, 1.0), -0.35, 0.35).

    // 7. Unit-sphere orthogonal thrust vector synthesis
    LOCAL u_theta IS SQRT(MAX(0.05, 1.0 - u_r * u_r - u_h * u_h)).
    LOCAL raw_steer IS (downrange_unit * u_theta + r_unit * u_r + h_horiz * u_h):NORMALIZED.

    // 8. First-order low-pass attitude smoothing
    LOCAL prev_steer IS upeg_state["prev_steer"].
    LOCAL smoothed_steer IS (prev_steer * 0.65 + raw_steer * 0.35):NORMALIZED.
    SET upeg_state["prev_steer"] TO smoothed_steer.

    // 9. SECO energy & velocity convergence check (with 1-tick lead compensation)
    LOCAL cutoff_lead_dv IS a_0 * 0.022.
    LOCAL spec_energy IS 0.5 * (v_vec:SQRMAGNITUDE) - grav_mu / r_mag.
    LOCAL target_energy IS -grav_mu / (2.0 * upeg_state["a_tgt"]).

    IF (v_theta >= v_tgt - cutoff_lead_dv AND ABS(v_radial) < 2.0) OR
       spec_energy >= target_energy - (v_theta * cutoff_lead_dv) {
        SET upeg_state["cutoff"] TO TRUE.
        SET upeg_state["cutoff_reason"] TO "ORBITAL_ENERGY_CONVERGED".
    } ELSE IF upeg_state["elapsed"] >= upeg_state["max_burn_time"] {
        SET upeg_state["cutoff"] TO TRUE.
        SET upeg_state["cutoff_reason"] TO "BURN_TIME_GUARD".
    }

    LOCAL top_ref IS vxcl(smoothed_steer, r_unit).
    IF top_ref:MAG < 0.001 {
        SET top_ref TO SHIP:NORTH:VECTOR.
    }
    RETURN LOOKDIRUP(smoothed_steer, top_ref:NORMALIZED).
}
