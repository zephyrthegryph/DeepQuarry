// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// From /obj/machinery/computer/arcade/prizevend(mob/user, prizes = 1)
ACTION(arcade_prizevend, user, FIXED, notice = /datum/notice/arcade_prizevend)

/// Non TG signals.
/// Hose Connector Component
ACTION(hose_forcepump, FIXED, notice = /datum/notice/hose_forcepump)

/// From /obj/machinery/atom_break(damage_flag): (damage_flag)
ACTION(machinery_broken, damage_flag, FIXED, notice = /datum/notice/machinery_broken)

/// From /obj/machinery/rnd/destructive_analyzer/proc/destroy_item(gain_research_points = FALSE): Runs when the destructive scanner scans a group of objects. (list/scanned_atoms)
ACTION(machinery_destructive_scan, scanned_atoms, FIXED, notice = /datum/notice/machinery_destructive_scan)

/// From /obj/machinery/doppler_array/proc/sense_explosion(): Runs when an explosion is detected. (turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken)
ACTION(machinery_explosion_detected, epicenter, devastation_range, heavy_impact_range, light_impact_range, seconds_taken, FIXED, notice = /datum/notice/machinery_explosion_detected)

/// From base power_change() when power is lost
ACTION(machinery_power_lost, FIXED, notice = /datum/notice/machinery_power_lost)

/// From base power_change() when power is restored
ACTION(machinery_power_restored, FIXED, notice = /datum/notice/machinery_power_restored)
