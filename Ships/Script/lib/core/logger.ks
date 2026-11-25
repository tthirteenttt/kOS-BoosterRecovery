// ============================================================================
// Telemetry and Event Logger
// ============================================================================

FUNCTION log_info {
    PARAMETER tag, msg_text.
    PRINT " [" + tag + "] " + msg_text.
}

FUNCTION log_warn {
    PARAMETER tag, msg_text.
    PRINT " [WARN: " + tag + "] " + msg_text.
}

FUNCTION log_error {
    PARAMETER tag, msg_text.
    PRINT " [ERROR: " + tag + "] " + msg_text.
}
