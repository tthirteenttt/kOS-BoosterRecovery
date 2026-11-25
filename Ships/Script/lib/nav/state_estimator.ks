// ============================================================================
// Navigation State Estimator & Landing Site Resolver (state_estimator.ks)
// ----------------------------------------------------------------------------
// Contract:
//   resolve_landing_site(site_config) -> Validated GeoCoordinates
//   get_corrected_radar_altitude(gear_offset, site_elevation) -> Footpad AGL (m)
//   get_dynamic_pressure() -> Dynamic pressure (kPa)
// ============================================================================

FUNCTION clamp_latitude {
    PARAMETER lat_val.
    RETURN MAX(-90.0, MIN(90.0, lat_val)).
}

FUNCTION normalize_longitude {
    PARAMETER lng_val.
    LOCAL lng IS lng_val.
    LOCAL guard IS 0.
    UNTIL (lng <= 180.0 AND lng >= -180.0) OR guard >= 20 {
        IF lng > 180.0 { SET lng TO lng - 360.0. }
        IF lng < -180.0 { SET lng TO lng + 360.0. }
        SET guard TO guard + 1.
    }
    RETURN lng.
}

FUNCTION resolve_landing_site {
    PARAMETER site_config.

    LOCAL base_lat IS clamp_latitude(site_config["LATITUDE"]).
    LOCAL base_lng IS normalize_longitude(site_config["LONGITUDE"]).

    LOCAL target_geo IS LATLNG(base_lat, base_lng).
    log_info("TARGET", "Landing Target: Lat " + ROUND(target_geo:LAT, 5) + ", Lng " + ROUND(target_geo:LNG, 5)).
    RETURN target_geo.
}

// Footpad height above effective landing surface (max of ocean 0m, terrain, and deck elevation)
FUNCTION get_corrected_radar_altitude {
    PARAMETER gear_offset, site_elevation IS 0.0.
    LOCAL ground_elev IS MAX(0.0, MAX(SHIP:GEOPOSITION:TERRAINHEIGHT, site_elevation)).
    LOCAL raw_radar IS SHIP:ALTITUDE - ground_elev.
    RETURN MAX(0.0, raw_radar - gear_offset).
}

// Live dynamic pressure in kPa (converted from kOS SHIP:Q in atm)
FUNCTION get_dynamic_pressure {
    RETURN SHIP:Q * CONSTANT:ATMtokPa.
}
