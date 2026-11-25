// ============================================================================
// MECO Cutoff Criteria & Time-to-MECO Predictor (staging_predictor.ks)
// ----------------------------------------------------------------------------
// Primary MECO trigger is stack SHIP:MASS <= MECO_MASS above MIN_MECO_ALT,
// backed by a Stage 1 propellant reserve floor guard.
// ============================================================================

// Minimum S1 propellant reserve (t) for fallback MECO guard
FUNCTION get_required_reserve_propellant {
    PARAMETER recovery_mode.

    IF recovery_mode = "RTLS" {
        RETURN 13.5.
    }
    RETURN 4.5.
}

// Estimated remaining Stage 1 propellant (t) from stack mass decrease
FUNCTION s1_propellant_remaining {
    PARAMETER current_mass, pad_mass, s1_propellant_mass.
    LOCAL s1_empty_stack_mass IS pad_mass - s1_propellant_mass.
    RETURN MAX(0.0, current_mass - s1_empty_stack_mass).
}

// Primary MECO trigger: stack mass reaches MECO_MASS above safety altitude
FUNCTION check_meco_by_mass {
    PARAMETER current_mass, meco_mass, current_alt, min_meco_alt.
    IF current_alt < min_meco_alt {
        RETURN FALSE.
    }
    RETURN current_mass <= meco_mass.
}

// Fallback MECO trigger: remaining Stage 1 propellant reaches reserve floor
FUNCTION check_meco_by_reserve {
    PARAMETER current_mass, pad_mass, s1_propellant_mass, reserve_mass, current_alt, min_meco_alt.
    IF current_alt < min_meco_alt {
        RETURN FALSE.
    }
    RETURN s1_propellant_remaining(current_mass, pad_mass, s1_propellant_mass) <= reserve_mass.
}

// Estimated time remaining to MECO (s) for HUD display
FUNCTION predict_mass_meco_time {
    PARAMETER current_mass, meco_mass, mass_flow_rate.
    IF mass_flow_rate <= 0.001 {
        RETURN 999.0.
    }
    RETURN MAX(0.0, (current_mass - meco_mass) / mass_flow_rate).
}
