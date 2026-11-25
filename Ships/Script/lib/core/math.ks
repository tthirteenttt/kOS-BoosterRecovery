// ============================================================================
// Core Vector and Scalar Math Utilities (math.ks)
// ============================================================================

FUNCTION clamp {
    PARAMETER val, min_val, max_val.
    RETURN MAX(min_val, MIN(max_val, val)).
}

FUNCTION safe_divide {
    PARAMETER num, denom, default_val.
    IF ABS(denom) < 0.00001 {
        RETURN default_val.
    }
    RETURN num / denom.
}

// Orthogonal projection of vec onto the plane perpendicular to normal_vec
FUNCTION vector_proj_plane {
    PARAMETER vec, normal_vec.
    LOCAL n_unit IS normal_vec:NORMALIZED.
    RETURN vec - (vec * n_unit) * n_unit.
}

FUNCTION get_horizontal_speed {
    PARAMETER vel_vector.
    LOCAL up_vector IS SHIP:UP:VECTOR.
    LOCAL horiz_v IS vector_proj_plane(vel_vector, up_vector).
    RETURN horiz_v:MAG.
}

// Singularity-safe unit vector normalization (never produces NaN)
FUNCTION safe_normalize {
    PARAMETER vec, fallback_vec.
    IF vec:MAG < 0.001 {
        IF fallback_vec:MAG < 0.001 {
            RETURN SHIP:UP:VECTOR.
        }
        RETURN fallback_vec:NORMALIZED.
    }
    RETURN vec:NORMALIZED.
}

// C1-smooth cubic Hermite step function (0 for x <= 0, 1 for x >= 1)
FUNCTION hermite_step {
    PARAMETER x_val.
    LOCAL s_clamped IS clamp(x_val, 0.0, 1.0).
    RETURN s_clamped * s_clamped * (3.0 - 2.0 * s_clamped).
}
