// ============================================================================
// Titanium Grid Fin Controller (KRE Grid Fin M Titanium)
// ----------------------------------------------------------------------------
// Handles grid fin deployment, roll-axis lockout (stock + FAR), and gentle
// dynamic-pressure authority scheduling.
// ============================================================================

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
    PARAMETER part_keyword IS "Grid Fin", event_keyword IS "Extend".

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
