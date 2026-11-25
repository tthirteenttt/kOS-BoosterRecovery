// ============================================================================
// Terminal ASCII HUD Display (hud_display.ks)
// Fixed 65-column width padding prevents scrolled log lines from bleeding
// into the top telemetry block.
// ============================================================================

FUNCTION render_hud {
    PARAMETER fsm_phase, radar_alt, vert_speed, horiz_speed, throt_val, mode_str, prop_left, t_go_val.

    PRINT "=================== Falcon 9 Flight Telemetry ===================" AT(0, 0).
    PRINT (" PHASE        : " + fsm_phase):PADRIGHT(65) AT(0, 1).
    PRINT (" MODE         : " + mode_str):PADRIGHT(65) AT(0, 2).
    PRINT (" RADAR ALT    : " + ROUND(radar_alt, 1) + " m"):PADRIGHT(65) AT(0, 3).
    PRINT (" VERT SPEED   : " + ROUND(vert_speed, 1) + " m/s"):PADRIGHT(65) AT(0, 4).
    PRINT (" HORIZ SPEED  : " + ROUND(horiz_speed, 1) + " m/s"):PADRIGHT(65) AT(0, 5).
    PRINT (" THROTTLE     : " + ROUND(throt_val * 100.0, 1) + " %"):PADRIGHT(65) AT(0, 6).
    PRINT (" PROPELLANT   : " + ROUND(prop_left, 1) + " t"):PADRIGHT(65) AT(0, 7).
    PRINT (" TIME TO GO   : " + ROUND(t_go_val, 1) + " s"):PADRIGHT(65) AT(0, 8).
    PRINT "=================================================================" AT(0, 9).
}
