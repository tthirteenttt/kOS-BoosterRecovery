// ============================================================================
// Engine Mode Switcher & Landing Leg Controller (Tundra F9 + KRE)
// ----------------------------------------------------------------------------
// Operates ModuleTundraEngineSwitch (0=AllEngines, 1=ThreeLanding, 2=CenterOnly)
// via PartModule:DOACTION, and idempotently extends KRE landing legs.
// ============================================================================

// Search module action list for a GUI name matching keyword or "Next"
FUNCTION find_module_action {
    PARAMETER pm, keyword.
    FOR nm IN pm:ALLACTIONNAMES {
        IF nm:CONTAINS(keyword) OR nm:CONTAINS("NEXT") OR nm:CONTAINS("next") {
            RETURN nm.
        }
    }
    RETURN "".
}

// Search module event list for a GUI name matching keyword or "Extend"
FUNCTION find_module_event {
    PARAMETER pm, keyword.
    FOR nm IN pm:ALLEVENTNAMES {
        IF nm:CONTAINS(keyword) OR nm:CONTAINS("EXTEND") OR nm:CONTAINS("extend") {
            RETURN nm.
        }
    }
    RETURN "".
}

FUNCTION get_s1_engine_part {
    FOR p IN SHIP:PARTS {
        IF p:NAME:CONTAINS("TE.19.F9.S1.Engine") OR p:NAME:CONTAINS("TE_19_F9_S1_Engine") {
            RETURN p.
        }
    }
    FOR eng IN SHIP:ENGINES {
        IF eng:MAXTHRUST > 2000.0 {
            RETURN eng:PART.
        }
    }
    RETURN SHIP:ROOTPART.
}

FUNCTION init_engine_manager {
    PARAMETER start_index.
    SET S1_ENGINE_MODE_INDEX TO MAX(0, MIN(2, start_index)).
    // Disable S1 engine gimbal roll actuation to prevent multi-engine roll chatter
    LOCAL eng_part IS get_s1_engine_part().
    IF eng_part:HASMODULE("ModuleGimbal") {
        LOCAL gim IS eng_part:GETMODULE("ModuleGimbal").
        IF gim:HASFIELD("enableRoll") {
            gim:SETFIELD("enableRoll", FALSE).
        }
    }
}

// Step engine mode forward from current index to target_mode_index (0 -> 1 -> 2)
FUNCTION set_engine_mode {
    PARAMETER target_mode_index.

    LOCAL target_idx IS MAX(0, MIN(2, target_mode_index)).
    LOCAL current_idx IS 0.
    IF DEFINED S1_ENGINE_MODE_INDEX {
        SET current_idx TO S1_ENGINE_MODE_INDEX.
    }
    LOCAL steps IS MAX(0, MIN(3, target_idx - current_idx)).
    IF steps <= 0 {
        RETURN.
    }

    LOCAL module_name IS "ModuleTundraEngineSwitch".
    LOCAL eng_part IS get_s1_engine_part().

    IF NOT eng_part:HASMODULE(module_name) {
        log_warn("ENGINE", "ModuleTundraEngineSwitch not found on S1 engine part.").
        RETURN.
    }
    LOCAL sw IS eng_part:GETMODULE(module_name).
    LOCAL next_action IS find_module_action(sw, "Next").
    IF next_action = "" AND sw:HASACTION("Next Engine Mode") {
        SET next_action TO "Next Engine Mode".
    }
    IF next_action = "" AND sw:HASACTION("NextEngineModeAction") {
        SET next_action TO "NextEngineModeAction".
    }
    IF next_action = "" {
        log_warn("ENGINE", "Cannot locate 'Next Engine Mode' action; mode unchanged.").
        RETURN.
    }

    // Ignition-count safety interlock: zero throttle and wait 0.25 s before mode switch
    IF DEFINED rec_throttle {
        SET rec_throttle TO 0.0.
    }
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.0.
    WAIT 0.25.

    LOCAL safety IS 0.
    UNTIL safety >= steps {
        sw:DOACTION(next_action, TRUE).
        SET safety TO safety + 1.
        WAIT 0.15.
    }
    SET S1_ENGINE_MODE_INDEX TO target_idx.
    log_info("ENGINE", "Engine mode switched to index " + target_idx + ".").
}

FUNCTION set_engine_mode_all {
    set_engine_mode(0).
}

FUNCTION set_engine_mode_three {
    set_engine_mode(1).
}

FUNCTION set_engine_mode_single {
    set_engine_mode(2).
}

// Extend landing legs safely (guards GEAR toggle state, then confirms via DOEVENT)
FUNCTION deploy_landing_legs {
    PARAMETER leg_keyword IS "FalconLeg", event_keyword IS "Extend".

    IF NOT GEAR {
        GEAR ON.
    }
    WAIT 0.1.

    FOR p IN SHIP:PARTS {
        IF p:NAME:CONTAINS(leg_keyword) {
            IF p:HASMODULE("ModuleWheelDeployment") {
                LOCAL wheel_mod IS p:GETMODULE("ModuleWheelDeployment").
                LOCAL ev_name IS find_module_event(wheel_mod, event_keyword).
                IF ev_name <> "" {
                    IF wheel_mod:HASEVENT(ev_name) {
                        wheel_mod:DOEVENT(ev_name).
                    }
                }
            }
        }
    }
    log_info("ACTUATOR", "Landing legs deployed.").
}
