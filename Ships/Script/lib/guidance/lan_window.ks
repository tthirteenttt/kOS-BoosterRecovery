// ============================================================================
// LAN Launch Window Solver & Better-Time-Warp Safe Auto-Warp (lan_window.ks) v1.1
// ============================================================================

FUNCTION wrap_360 {
    PARAMETER ang.
    LOCAL ang_norm IS MOD(ang, 360.0).
    IF ang_norm < 0.0 { SET ang_norm TO ang_norm + 360.0. }
    RETURN ang_norm.
}

// Compute Earth inertial equatorial orthonormal basis (X=LAN 0, Z=LAN 90, N=North)
FUNCTION get_inertial_equatorial_basis {
    LOCAL north_pole IS -SHIP:BODY:ANGULARVEL:NORMALIZED.
    LOCAL x_axis IS vxcl(north_pole, SOLARPRIMEVECTOR):NORMALIZED.
    LOCAL z_axis IS VCRS(x_axis, north_pole):NORMALIZED.
    RETURN LEXICON("N", north_pole, "X", x_axis, "Z", z_axis).
}

// Instantaneous launchpad LAN for target inclination & ascending/descending branch
FUNCTION compute_launchpad_lan {
    PARAMETER inc_deg, go_south.

    LOCAL basis IS get_inertial_equatorial_basis().
    LOCAL r_pad IS SHIP:POSITION - SHIP:BODY:POSITION.
    LOCAL r_eq IS vxcl(basis["N"], r_pad).
    LOCAL pad_ra IS wrap_360(ARCTAN2(r_eq * basis["Z"], r_eq * basis["X"])).

    LOCAL lat IS SHIP:GEOPOSITION:LAT.
    LOCAL eff_inc IS MAX(ABS(lat), MIN(180.0 - ABS(lat), ABS(inc_deg))).
    LOCAL sin_dlon IS clamp(TAN(lat) * COS(eff_inc) / MAX(SIN(eff_inc), 0.0001), -1.0, 1.0).
    LOCAL dlon IS ARCSIN(sin_dlon).

    IF go_south {
        RETURN wrap_360(pad_ra + dlon + 180.0).
    }
    RETURN wrap_360(pad_ra - dlon).
}

// Compute remaining rotation angle (deg) and wait time (s) to launch window
FUNCTION compute_lan_window_status {
    PARAMETER inc_deg, tgt_lan, go_south, lead_time_s.

    LOCAL rot_deg_s IS SHIP:BODY:ANGULARVEL:MAG * (180.0 / CONSTANT:PI).
    LOCAL cur_lan IS compute_launchpad_lan(inc_deg, go_south).
    LOCAL launch_lan IS wrap_360(tgt_lan - rot_deg_s * MAX(0.0, lead_time_s)).

    LOCAL d_lan IS wrap_360(launch_lan - cur_lan).
    // Within 0.25 deg (~60s) past trigger: treat as in-window to prevent 24h wrap
    IF d_lan > 359.75 {
        SET d_lan TO 0.0.
    }
    LOCAL t_wait IS d_lan / MAX(rot_deg_s, 0.000001).

    RETURN LEXICON(
        "CUR_LAN", cur_lan,
        "TGT_LAN", wrap_360(tgt_lan),
        "LAUNCH_LAN", launch_lan,
        "DELTA_LAN", d_lan,
        "T_WAIT", t_wait,
        "GO_SOUTH", go_south
    ).
}

// Resolve ascending/descending launch branch ("AUTO" / "NEAREST" / TRUE / FALSE)
FUNCTION resolve_launch_south_branch {
    PARAMETER geo_pos, inc_deg, south_mode, tgt_lan, lead_time_s, is_fixed_lan.

    LOCAL lat IS geo_pos:LAT.
    LOCAL eff_inc IS MAX(ABS(lat), MIN(180.0 - ABS(lat), ABS(inc_deg))).

    IF south_mode = TRUE { RETURN TRUE. }
    IF south_mode = FALSE { RETURN FALSE. }

    // Vandenberg high-inclination coastal range safety: force southbound
    IF lat > 32.0 AND lat < 36.0 AND geo_pos:LNG < -119.0 AND eff_inc > 60.0 {
        RETURN TRUE.
    }

    IF is_fixed_lan AND south_mode = "NEAREST" {
        LOCAL w_asc IS compute_lan_window_status(inc_deg, tgt_lan, FALSE, lead_time_s).
        LOCAL w_desc IS compute_lan_window_status(inc_deg, tgt_lan, TRUE, lead_time_s).
        IF w_desc["T_WAIT"] < w_asc["T_WAIT"] {
            RETURN TRUE.
        }
    }
    RETURN FALSE.
}

// Launchpad LAN wait loop (monotonic target_ut + live RAILSRATELIST safe warp)
FUNCTION wait_for_lan_window {
    PARAMETER inc_deg, tgt_lan, go_south, lead_time_s, auto_warp.

    LOCAL branch_str IS "ASCENDING (North)".
    IF go_south { SET branch_str TO "DESCENDING (South)". }

    CLEARSCREEN.
    PRINT "==================================================" AT(0, 0).
    PRINT "   LAN Launch Window Guidance (Plane Alignment)   " AT(0, 1).
    PRINT "==================================================" AT(0, 2).
    PRINT "Target Inclination : " + ROUND(inc_deg, 2) + " deg | " + branch_str AT(0, 4).
    PRINT "Target Orbit LAN   : " + ROUND(wrap_360(tgt_lan), 3) + " deg" AT(0, 5).
    PRINT "Lead Time Comp     : " + ROUND(lead_time_s, 1) + " s" AT(0, 6).
    IF auto_warp {
        PRINT "Warp Policy        : AUTO-WARP (Max 10000x, Stop T-12s)" AT(0, 7).
    } ELSE {
        PRINT "Warp Policy        : MANUAL WARP (Auto-Stop active)" AT(0, 7).
    }
    PRINT "--------------------------------------------------" AT(0, 8).

IF KUNIVERSE:TIMEWARP:MODE <> "RAILS" {
        SET KUNIVERSE:TIMEWARP:MODE TO "RAILS".
        WAIT 0.
    }

    // Lock monotonic target UT once; prevents 24h wrap-around infinite warp on overshoot
    LOCAL init_st IS compute_lan_window_status(inc_deg, tgt_lan, go_south, lead_time_s).
    LOCAL target_ut IS TIME:SECONDS + init_st["T_WAIT"].

    LOCAL in_window IS FALSE.
    UNTIL in_window {
        LOCAL st IS compute_lan_window_status(inc_deg, tgt_lan, go_south, lead_time_s).
        LOCAL t_rem IS target_ut - TIME:SECONDS.

        // Gentle drift sync only far from window and strictly guarding against wrap-around
        IF t_rem > 45.0 AND ABS(st["T_WAIT"] - t_rem) < 120.0 {
            SET target_ut TO TIME:SECONDS + st["T_WAIT"].
            SET t_rem TO st["T_WAIT"].
        }

        LOCAL t_disp IS MAX(0.0, t_rem).
        LOCAL hrs IS FLOOR(t_disp / 3600.0).
        LOCAL mins IS FLOOR(MOD(t_disp, 3600.0) / 60.0).
        LOCAL secs IS ROUND(MOD(t_disp, 60.0), 1).

        PRINT "Current Pad LAN    : " + ROUND(st["CUR_LAN"], 3) + " deg        " AT(0, 9).
        PRINT "Launch Trigger LAN : " + ROUND(st["LAUNCH_LAN"], 3) + " deg        " AT(0, 10).
        PRINT "Delta LAN to Go    : " + ROUND(st["DELTA_LAN"], 3) + " deg        " AT(0, 11).
        PRINT "Window T-Minus     : " + hrs + "h " + mins + "m " + secs + "s (" + ROUND(t_disp, 1) + " s)      " AT(0, 12).
        PRINT "Time Warp Rate     : " + ROUND(KUNIVERSE:TIMEWARP:RATE, 0) + "x (Lv " + KUNIVERSE:TIMEWARP:WARP + ")        " AT(0, 13).

        IF t_rem <= 0.5 {
            IF KUNIVERSE:TIMEWARP:WARP > 0 {
                KUNIVERSE:TIMEWARP:CANCELWARP().
            }
            IF KUNIVERSE:TIMEWARP:WARP = 0 AND KUNIVERSE:TIMEWARP:ISSETTLED {
                SET in_window TO TRUE.
            }
        } ELSE {
            // Query live RATELIST for RAILS mode (compatible with Better Time Warp / RSS)
            LOCAL rates IS KUNIVERSE:TIMEWARP:RATELIST.
            LOCAL max_safe_warp IS 0.
            LOCAL warp_budget IS t_rem - 12.0.
            IF warp_budget > 0.0 {
                FROM { LOCAL idx IS 1. } UNTIL idx >= rates:LENGTH STEP { SET idx TO idx + 1. } DO {
                    LOCAL w_rate IS rates[idx].
                    IF w_rate <= 10000.0 AND (w_rate * 3.5) <= warp_budget {
                        SET max_safe_warp TO idx.
                    }
                }
            }

            IF auto_warp {
                IF max_safe_warp = 0 {
                    IF KUNIVERSE:TIMEWARP:WARP > 0 {
                        KUNIVERSE:TIMEWARP:CANCELWARP().
                    }
                } ELSE IF KUNIVERSE:TIMEWARP:WARP > max_safe_warp {
                    // Always step DOWN immediately regardless of ISSETTLED
                    SET KUNIVERSE:TIMEWARP:WARP TO max_safe_warp.
                } ELSE IF KUNIVERSE:TIMEWARP:WARP < max_safe_warp AND KUNIVERSE:TIMEWARP:ISSETTLED {
                    // Step UP cleanly once previous transition settles
                    SET KUNIVERSE:TIMEWARP:WARP TO max_safe_warp.
                }
            } ELSE {
                IF KUNIVERSE:TIMEWARP:WARP > max_safe_warp {
                    IF max_safe_warp = 0 {
                        KUNIVERSE:TIMEWARP:CANCELWARP().
                    } ELSE {
                        SET KUNIVERSE:TIMEWARP:WARP TO max_safe_warp.
                    }
                }
            }
        }
        WAIT 0.02.
    }

    PRINT ">>> LAN WINDOW REACHED! PROCEEDING TO IGNITION <<<" AT(0, 15).
    WAIT 0.5.
}