// ============================================================================
// Scalar PID Controller Wrapper (kOS built-in PIDLOOP)
// ----------------------------------------------------------------------------
// Contract:
//   create_pid(kp, ki, kd, min_out, max_out) -> PIDLoop
//   update_pid(pid_state, err)               -> Scalar output proportional to err
//   reset_pid(pid_state)                     -> Reset integral accumulator
// ============================================================================

FUNCTION create_pid {
    PARAMETER kp, ki, kd, min_out, max_out.
    RETURN PIDLOOP(kp, ki, kd, min_out, max_out).
}

// PIDLoop computes error = SETPOINT - INPUT; passing SETPOINT=0 and INPUT=-err
// makes output directly proportional to signed error.
FUNCTION update_pid {
    PARAMETER pid_state, err.
    SET pid_state:SETPOINT TO 0.
    RETURN pid_state:UPDATE(TIME:SECONDS, -err).
}

FUNCTION reset_pid {
    PARAMETER pid_state.
    pid_state:RESET().
}
