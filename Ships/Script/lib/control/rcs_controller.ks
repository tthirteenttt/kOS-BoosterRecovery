// ============================================================================
// Cold-Gas RCS Controller v0.6 —— Strict ASDS / RTLS Decoupled Coast Logic
// ============================================================================

FUNCTION set_rcs_state {
    PARAMETER enabled_flag.
    IF enabled_flag {
        IF NOT RCS { RCS ON. }
    } ELSE {
        IF RCS { RCS OFF. }
    }
}

FUNCTION get_nitrogen_amount {
    LOCAL n2_total IS 0.0.
    FOR res IN SHIP:RESOURCES {
        IF res:NAME = "Nitrogen" {
            SET n2_total TO n2_total + res:AMOUNT.
        }
    }
    RETURN n2_total.
}

FUNCTION init_rcs_controller_state {
    RETURN LEXICON(
        "ACTIVE", TRUE,
        "LAST_STATE", "",
        "PREV_ERR", -1.0,
        "PREV_TIME", TIME:SECONDS,
        "CLOSING_RATE", 0.0,
        "COAST_DRIFT_LOCK", FALSE,
        "COAST_ENTER_TIME", TIME:SECONDS
    ).
}

FUNCTION manage_rcs_by_dynamic_pressure {
    PARAMETER q_cutoff, steer_target IS V(0,0,0), was_on IS TRUE.

    LOCAL q_off IS MAX(0.03, q_cutoff).
    LOCAL q_on IS MAX(0.02, q_off * 0.67).
    LOCAL dyn_q IS SHIP:Q.

    LOCAL fore_vec IS SHIP:FACING:VECTOR.
    LOCAL ang_vel IS SHIP:ANGULARVEL.
    LOCAL roll_rate_deg IS ABS((ang_vel * fore_vec) * (180.0 / CONSTANT:PI)).
    LOCAL py_rate_deg IS vxcl(fore_vec, ang_vel):MAG * (180.0 / CONSTANT:PI).
    LOCAL att_err IS 0.0.
    IF steer_target:MAG > 0.001 {
        SET att_err TO VANG(fore_vec, steer_target).
    }

    // 1. High-altitude rarefied atmosphere or low dynamic pressure (with hysteresis)
    IF SHIP:ALTITUDE > 50000.0 OR dyn_q < q_on {
        set_rcs_state(TRUE).
        RETURN TRUE.
    }

    // 2. Grid-fin dominant regime: pitch/yaw large-upset guard + roll-rate guard (grid fins rollaxis=0)
    LOCAL want_on IS was_on.
    IF was_on {
        IF dyn_q >= q_off AND att_err < 12.0 AND py_rate_deg < 8.0 AND roll_rate_deg < 4.0 {
            SET want_on TO FALSE.
        }
    } ELSE {
        IF att_err > 20.0 OR py_rate_deg > 18.0 OR roll_rate_deg > 12.0 {
            SET want_on TO TRUE.
        }
    }

    set_rcs_state(want_on).
    RETURN want_on.
}

FUNCTION manage_rcs_high_alt {
    PARAMETER cur_state, q_cutoff, high_steer_target, aero_steer_target, rcs_state, rec_mode IS "ASDS", eb_start_alt IS 68000.0.

    IF cur_state = "ST_AERO_GLIDE" {
        LOCAL low_on IS manage_rcs_by_dynamic_pressure(q_cutoff, aero_steer_target, rcs_state["ACTIVE"]).
        SET rcs_state["ACTIVE"] TO low_on.
        RETURN low_on.
    }
    IF cur_state = "ST_LANDING_BURN" {
        LOCAL fore_l IS SHIP:FACING:VECTOR.
        LOCAL roll_deg_s IS ABS((SHIP:ANGULARVEL * fore_l) * (180.0 / CONSTANT:PI)).
        LOCAL land_att_err IS 0.0.
        IF aero_steer_target:MAG > 0.001 {
            SET land_att_err TO VANG(fore_l, aero_steer_target).
        }
        LOCAL dyn_q_l IS SHIP:Q.
        LOCAL was_land_on IS rcs_state["ACTIVE"].
        LOCAL land_rcs IS was_land_on.

        // Re-engage RCS at low speed (q < 0.015 atm, ~V < 50 m/s ASL) as grid fins lose authority,
        // or during spool-up if dynamic pressure is already low.
        IF dyn_q_l < 0.015 OR (SHIP:THRUST < 100.0 AND dyn_q_l < 0.06) {
            SET land_rcs TO TRUE.
        } ELSE IF was_land_on {
            IF dyn_q_l >= 0.022 AND land_att_err < 4.5 AND roll_deg_s < 3.0 {
                SET land_rcs TO FALSE.
            }
        } ELSE {
            IF land_att_err > 9.0 OR roll_deg_s > 8.0 {
                SET land_rcs TO TRUE.
            }
        }
        set_rcs_state(land_rcs).
        SET rcs_state["ACTIVE"] TO land_rcs.
        RETURN land_rcs.
    }
    IF cur_state = "ST_TOUCHDOWN" {
        set_rcs_state(FALSE).
        SET rcs_state["ACTIVE"] TO FALSE.
        RETURN FALSE.
    }

    LOCAL att_err IS 0.0.
    IF high_steer_target:MAG > 0.001 {
        SET att_err TO VANG(SHIP:FACING:VECTOR, high_steer_target).
    }
    LOCAL ang_vel IS SHIP:ANGULARVEL.
    LOCAL fore_vec IS SHIP:FACING:VECTOR.
    LOCAL roll_rate_deg IS ABS((ang_vel * fore_vec) * (180.0 / CONSTANT:PI)).
    LOCAL py_rate_deg IS vxcl(fore_vec, ang_vel):MAG * (180.0 / CONSTANT:PI).

    IF rcs_state["LAST_STATE"] <> cur_state {
        SET rcs_state["LAST_STATE"] TO cur_state.
        SET rcs_state["PREV_ERR"] TO att_err.
        SET rcs_state["PREV_TIME"] TO TIME:SECONDS.
        SET rcs_state["CLOSING_RATE"] TO 0.0.
        SET rcs_state["COAST_DRIFT_LOCK"] TO FALSE.
        SET rcs_state["COAST_ENTER_TIME"] TO TIME:SECONDS.
    } ELSE {
        LOCAL dt_rate IS TIME:SECONDS - rcs_state["PREV_TIME"].
        IF dt_rate >= 0.08 {
            LOCAL raw_closing IS (rcs_state["PREV_ERR"] - att_err) / dt_rate.
            SET rcs_state["CLOSING_RATE"] TO rcs_state["CLOSING_RATE"] * 0.65 + raw_closing * 0.35.
            SET rcs_state["PREV_ERR"] TO att_err.
            SET rcs_state["PREV_TIME"] TO TIME:SECONDS.
        }
    }

    LOCAL closing_rate IS rcs_state["CLOSING_RATE"].
    LOCAL was_on IS rcs_state["ACTIVE"].
    LOCAL want_on IS was_on.

    IF cur_state = "ST_FLIP" {
        IF rec_mode = "RTLS" {
            SET want_on TO TRUE.
        } ELSE {
            // ASDS Bang-Coast-Bang inertial flip (UNTOUCHED)
            LOCAL target_flip_rate IS 6.5.
            IF att_err > 35.0 {
                IF was_on {
                    IF closing_rate >= target_flip_rate AND roll_rate_deg < 4.0 {
                        SET want_on TO FALSE.
                    }
                } ELSE {
                    IF closing_rate < (target_flip_rate - 2.0) OR roll_rate_deg > 6.0 {
                        SET want_on TO TRUE.
                    }
                }
            } ELSE {
                SET want_on TO TRUE.
            }
        }
    }
    ELSE IF cur_state = "ST_COAST" {
        // Trigger pre-entry alignment 14 km above each mode's Entry Burn interface
        // (ASDS: 68+14 = 82 km UNTOUCHED | RTLS: 58+14 = 72 km)
        LOCAL pre_entry_trim IS (SHIP:ALTITUDE < (eb_start_alt + 14000.0) AND SHIP:VERTICALSPEED < 0.0).
        IF pre_entry_trim {
            SET rcs_state["COAST_DRIFT_LOCK"] TO FALSE.
            SET want_on TO TRUE.
        } ELSE IF rec_mode = "RTLS" {
            // Post-boostback flip uses Bang-Coast-Bang inertial coast to save N2
            LOCAL coast_elapsed IS TIME:SECONDS - rcs_state["COAST_ENTER_TIME"].
            IF NOT rcs_state["COAST_DRIFT_LOCK"] {
                IF att_err > 28.0 {
                    LOCAL rtls_flip_rate IS 5.0.
                    IF was_on {
                        IF closing_rate >= rtls_flip_rate AND roll_rate_deg < 4.0 {
                            SET want_on TO FALSE.
                        }
                    } ELSE {
                        IF closing_rate < (rtls_flip_rate - 2.0) OR roll_rate_deg > 6.0 {
                            SET want_on TO TRUE.
                        }
                    }
                } ELSE {
                    IF (att_err < 12.0 AND py_rate_deg < 1.5) OR (coast_elapsed > 35.0 AND att_err < 22.0) {
                        SET rcs_state["COAST_DRIFT_LOCK"] TO TRUE.
                        SET want_on TO FALSE.
                    } ELSE {
                        SET want_on TO TRUE.
                    }
                }
            } ELSE {
                IF att_err > 45.0 OR py_rate_deg > 5.0 {
                    SET rcs_state["COAST_DRIFT_LOCK"] TO FALSE.
                    SET want_on TO TRUE.
                } ELSE {
                    SET want_on TO FALSE.
                }
            }
        } ELSE {
            // ASDS coast hysteresis with inertial drift lock
            LOCAL coast_elapsed IS TIME:SECONDS - rcs_state["COAST_ENTER_TIME"].
            IF NOT rcs_state["COAST_DRIFT_LOCK"] {
                IF (att_err < 12.0 AND py_rate_deg < 1.2) OR (coast_elapsed > 10.0 AND att_err < 25.0) {
                    SET rcs_state["COAST_DRIFT_LOCK"] TO TRUE.
                    SET want_on TO FALSE.
                } ELSE {
                    SET want_on TO TRUE.
                }
            } ELSE {
                IF att_err > 45.0 OR py_rate_deg > 5.0 {
                    SET rcs_state["COAST_DRIFT_LOCK"] TO FALSE.
                    SET want_on TO TRUE.
                } ELSE {
                    SET want_on TO FALSE.
                }
            }
        }
    }
    ELSE IF cur_state = "ST_BOOSTBACK" OR cur_state = "ST_ENTRY_BURN" {
        IF SHIP:THRUST > 400.0 {
            IF was_on {
                IF att_err < 5.0 AND roll_rate_deg < 2.5 {
                    SET want_on TO FALSE.
                }
            } ELSE {
                IF att_err > 12.0 OR roll_rate_deg > 6.0 {
                    SET want_on TO TRUE.
                }
            }
        } ELSE {
            SET want_on TO TRUE.
        }
    }

    SET rcs_state["ACTIVE"] TO want_on.
    set_rcs_state(want_on).
    RETURN want_on.
}