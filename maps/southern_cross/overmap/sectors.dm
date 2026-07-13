// The Sif planet overmap object was removed with the planetary surface z-levels
// (station-only trim, 2026-07-01). Its only placement was on the (now-removed)
// Plains z-level in southern_cross-3.dmm.

/obj/effect/overmap/visitable/Southern_Cross
	name = "Southern Cross"
	icon_state = "object"
	base = 1
	in_space = 1
	start_x =  10
	start_y =  10
	map_z = list(Z_LEVEL_STATION_ONE, Z_LEVEL_STATION_TWO, Z_LEVEL_STATION_THREE)
	extra_z_levels = list(Z_LEVEL_TRANSIT) // Hopefully temporary, so arrivals announcements work.
