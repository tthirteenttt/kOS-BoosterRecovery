// ============================================================================
// Titanium Grid Fin Controller (KRE Grid Fin M Titanium)
// ----------------------------------------------------------------------------
// Handles grid fin deployment, roll-axis lockout (stock + FAR), and gentle
// dynamic-pressure authority scheduling.
// ============================================================================

// Locate FARControllableSurface's "Std. Ctrl" toggle field (locale-independent:
// matches "Std. Ctrl" or falls back to the 2nd Boolean field in ALLFIELDNAMES,
// since FAR declares showFlpCtrl [0] immediately before showStdCtrl [1]).
FUNCTION find_far_std_ctrl_field {
    PARAMETER far_ctrl.
    IF far_ctrl:HASFIELD("Std. Ctrl") {
        RETURN "Std. Ctrl".
    }
    LOCAL bool_idx IS 0.
    FOR fn IN far_ctrl:ALLFIELDNAMES {
        IF far_ctrl:GETFIELD(fn):ISTYPE("Boolean") {
            IF bool_idx = 1 {
                RETURN fn.
            }
            SET bool_idx TO bool_idx + 1.
        }
    }
    RETURN "".
}

// Locate FARControllableSurface's "Ctrl Dflct" (maxdeflect) field once Std. Ctrl is expanded.
// FAR declares [pitchaxis, yawaxis, rollaxis, pitchaxisDueToAoA, brakeRudder, maxdeflect]
// immediately preceding the 1st Boolean field (showFlpCtrl).
FUNCTION find_far_deflect_field {
    PARAMETER far_ctrl.
    IF far_ctrl:HASFIELD("Ctrl Dflct") {
        RETURN "Ctrl Dflct".
    }
    IF far_ctrl:HASFIELD("Ctrl Aslnk") {
        RETURN "Ctrl Aslnk".
    }
    LOCAL names IS far_ctrl:ALLFIELDNAMES.
    LOCAL first_bool_idx IS -1.
    FROM { LOCAL i IS 0. } UNTIL i >= names:LENGTH STEP { SET i TO i + 1. } DO {
        IF far_ctrl:GETFIELD(names[i]):ISTYPE("Boolean") {
            SET first_bool_idx TO i.
            BREAK.
        }
    }
    IF first_bool_idx >= 6 {
        LOCAL cand IS names[first_bool_idx - 1].
        IF far_ctrl:GETFIELD(cand):ISTYPE("Scalar") {
            RETURN cand.
        }
    }
    RETURN "".
}

// Locate FARControllableSurface's "Roll %" (rollaxis) field once Std. Ctrl is expanded.
FUNCTION find_far_roll_field {
    PARAMETER far_ctrl.
    IF far_ctrl:HASFIELD("Roll %") {
        RETURN "Roll %".
    }
    LOCAL names IS far_ctrl:ALLFIELDNAMES.
    LOCAL first_bool_idx IS -1.
    FROM { LOCAL i IS 0. } UNTIL i >= names:LENGTH STEP { SET i TO i + 1. } DO {
        IF far_ctrl:GETFIELD(names[i]):ISTYPE("Boolean") {
            SET first_bool_idx TO i.
            BREAK.
        }
    }
    IF first_bool_idx >= 6 {
        LOCAL cand IS names[first_bool_idx - 4].
        IF far_ctrl:GETFIELD(cand):ISTYPE("Scalar") {
            RETURN cand.
        }
    }
    RETURN "".
}

// Set grid fin FAR max deflection angle (0 deg stowed on ascent -> 25 deg on deploy).
// Temporarily expands FAR's Std. Ctrl toggle so maxdeflect becomes guiActive, writes
// the target deflection (and locks FAR rollaxis = 0), then restores the PAW toggle state.
FUNCTION set_gridfin_deflection {
    PARAMETER target_deg, part_keyword IS "Grid Fin".

    LOCAL clamped_deg IS MAX(0.0, MIN(40.0, ROUND(target_deg * 2.0) / 2.0)).
    LOCAL far_entries IS LIST().
    LOCAL stock_updated IS 0.

    // Pass 0: snapshot initial Std. Ctrl state on all grid fins before toggling (symmetry-safe)
    FOR p IN SHIP:PARTS {
        IF p:NAME:CONTAINS("Grid Fin") OR p:NAME:CONTAINS("GridFin") OR p:NAME:CONTAINS(part_keyword) {
            IF p:HASMODULE("FARControllableSurface") {
                LOCAL far_ctrl IS p:GETMODULE("FARControllableSurface").
                LOCAL std_fn IS find_far_std_ctrl_field(far_ctrl).
                IF std_fn <> "" {
                    far_entries:ADD(LEXICON(
                        "MOD", far_ctrl,
                        "STD_FIELD", std_fn,
                        "WAS_OPEN", far_ctrl:GETFIELD(std_fn)
                    )).
                }
            } ELSE IF p:HASMODULE("ModuleControlSurface") {
                LOCAL ctrl IS p:GETMODULE("ModuleControlSurface").
                LOCAL stock_pct IS 0.0.
                IF clamped_deg > 0.1 { SET stock_pct TO 100.0. }
                IF ctrl:HASFIELD("authorityLimiter") {
                    ctrl:SETFIELD("authorityLimiter", stock_pct).
                    SET stock_updated TO stock_updated + 1.
                } ELSE IF ctrl:HASFIELD("Authority Limiter") {
                    ctrl:SETFIELD("Authority Limiter", stock_pct).
                    SET stock_updated TO stock_updated + 1.
                }
            }
        }
    }

    LOCAL far_updated IS 0.
    IF far_entries:LENGTH > 0 {
        // Pass 1: expand Std. Ctrl so FAR CheckFieldVisibility() sets maxdeflect.guiActive = TRUE
        LOCAL any_opened IS FALSE.
        FOR entry IN far_entries {
            LOCAL far_ctrl IS entry["MOD"].
            LOCAL std_fn IS entry["STD_FIELD"].
            IF NOT far_ctrl:GETFIELD(std_fn) {
                far_ctrl:SETFIELD(std_fn, TRUE).
                SET any_opened TO TRUE.
            }
        }
        IF any_opened {
            WAIT 0.05.
        }

        // Pass 2: write maxdeflect (Ctrl Dflct) and ensure FAR rollaxis = 0.0
        FOR entry IN far_entries {
            LOCAL far_ctrl IS entry["MOD"].
            LOCAL deflect_fn IS find_far_deflect_field(far_ctrl).
            IF deflect_fn <> "" {
                far_ctrl:SETFIELD(deflect_fn, clamped_deg).
                SET far_updated TO far_updated + 1.
            }
            LOCAL roll_fn IS find_far_roll_field(far_ctrl).
            IF roll_fn <> "" {
                far_ctrl:SETFIELD(roll_fn, 0.0).
            }
        }

        // Pass 3: restore original Std. Ctrl collapsed state to keep PAW tidy
        FOR entry IN far_entries {
            IF NOT entry["WAS_OPEN"] {
                LOCAL far_ctrl IS entry["MOD"].
                LOCAL std_fn IS entry["STD_FIELD"].
                IF far_ctrl:GETFIELD(std_fn) {
                    far_ctrl:SETFIELD(std_fn, FALSE).
                }
            }
        }
    }

    LOCAL total_updated IS far_updated + stock_updated.
    IF total_updated > 0 {
        log_info("AERO", "Grid fin Ctrl Deflect set to " + ROUND(clamped_deg, 1) +
                         " deg (" + total_updated + " fins).").
    }
    RETURN total_updated.
}

FUNCTION disable_part_roll {
    PARAMETER p.
    // Lock roll actuation on stock ModuleControlSurface (English & CN KSP locales) and FAR
    IF p:HASMODULE("ModuleControlSurface") {
        LOCAL ctrl IS p:GETMODULE("ModuleControlSurface").
        FOR fn IN ctrl:ALLFIELDNAMES {
            IF fn:CONTAINS("Roll") OR fn:CONTAINS("roll") OR fn:CONTAINS("滚转") {
                IF fn:CONTAINS("ignore") OR fn:CONTAINS("Ignore") {
                    ctrl:SETFIELD(fn, TRUE).
                }
            }
        }
    }
    IF p:HASMODULE("FARControllableSurface") {
        LOCAL far_ctrl IS p:GETMODULE("FARControllableSurface").
        IF far_ctrl:HASFIELD("rollaxis") {
            far_ctrl:SETFIELD("rollaxis", 0.0).
        }
    }
}

FUNCTION deploy_grid_fins {
    PARAMETER part_keyword IS "Grid Fin", event_keyword IS "Extend", deploy_deflect IS 25.0.

    LOCAL deployed IS 0.
    FOR p IN SHIP:PARTS {
        IF p:NAME:CONTAINS("Grid Fin") OR p:NAME:CONTAINS("GridFin") OR p:NAME:CONTAINS(part_keyword) {
            IF p:HASMODULE("ModuleAnimateGeneric") {
                LOCAL anim IS p:GETMODULE("ModuleAnimateGeneric").
                LOCAL ev_name IS find_module_event(anim, event_keyword).
                IF ev_name = "" AND anim:HASEVENT("Extend Fins") {
                    SET ev_name TO "Extend Fins".
                }
                IF ev_name <> "" AND anim:HASEVENT(ev_name) {
                    anim:DOEVENT(ev_name).
                    SET deployed TO deployed + 1.
                }
            }
            disable_part_roll(p).
        }
    }
    set_gridfin_deflection(deploy_deflect, part_keyword).
    log_info("AERO", "Grid fins deployed (" + deployed + ").").
}

// Schedule grid fin deflection authority with dynamic pressure (preserves >=65% subsonic)
FUNCTION tune_gridfin_authority {
    PARAMETER dyn_q, min_pct IS 65.0.

    LOCAL pct IS MAX(min_pct, MIN(100.0, 100.0 / (1.0 + MAX(0.0, dyn_q) * 1.5))).
    FOR p IN SHIP:PARTS {
        IF p:NAME:CONTAINS("Grid Fin") OR p:NAME:CONTAINS("GridFin") {
            IF p:HASMODULE("ModuleControlSurface") {
                LOCAL ctrl IS p:GETMODULE("ModuleControlSurface").
                IF ctrl:HASFIELD("authorityLimiter") {
                    ctrl:SETFIELD("authorityLimiter", pct).
                }
                IF ctrl:HASFIELD("Authority Limiter") {
                    ctrl:SETFIELD("Authority Limiter", pct).
                }
            }
        }
    }
    RETURN pct.
}
