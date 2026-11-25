// ============================================================================
// Discrete Finite State Machine (FSM) Helper
// ============================================================================

FUNCTION make_fsm {
    PARAMETER initial_state.
    LOCAL self IS LEXICON(
        "current_state", initial_state,
        "state_time", TIME:SECONDS,
        "transition_count", 0
    ).
    RETURN self.
}

FUNCTION transition_fsm {
    PARAMETER fsm_state, new_state.
    PRINT " [FSM] " + fsm_state["current_state"] + " -> " + new_state.
    SET fsm_state["current_state"] TO new_state.
    SET fsm_state["state_time"] TO TIME:SECONDS.
    SET fsm_state["transition_count"] TO fsm_state["transition_count"] + 1.
}

FUNCTION fsm_elapsed {
    PARAMETER fsm_state.
    RETURN TIME:SECONDS - fsm_state["state_time"].
}
