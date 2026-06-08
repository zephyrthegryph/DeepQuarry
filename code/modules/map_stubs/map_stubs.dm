// Map stubs for removed map content.
//
// When we removed the DME includes for Southern Cross / Tether / Stellar Delight /
// etc., some of those files defined parent classes and registry types that are
// still referenced from KEPT files (common_submaps, mapping subsystem). This
// module provides minimal stub definitions so the build succeeds.
//
// These types do nothing at runtime; their map content is just gone.

// Parent class for "late load" maps (common_submaps, dynamic overmap pois, engine subbays).
/datum/map_template/common_lateload
	allow_duplicates = FALSE
	var/associated_map_datum

/datum/map_template/common_lateload/on_map_loaded(z)
	if(!associated_map_datum || !ispath(associated_map_datum))
		return
	new associated_map_datum(using_map, z)

// Dynamic overmap POI template. The real base + 40 POI templates lived in
// maps/overmap/space_pois/space_pois.dm (areas in space_areas.dm), deleted in the
// "Tier 2 cleanup" (35c6976694). The dynamic-sector system that consumes them
// (code/modules/overmap/dynamic_sector.dm) is intact but DISABLED at its hook in
// code/modules/overmap/sectors.dm pending content restoration. This stub keeps
// dynamic_sector.dm compiling. To revive: recover space_pois.dm + space_areas.dm +
// loot_vr.dm from git, delete this stub, and re-enable the sectors.dm hook.
/datum/map_template/dynamic_overmap
	var/scanner_desc = "You should not see this."
	var/block_size = 0
	var/poi_icon
	var/poi_color
	var/active_icon
	var/faction
	var/list/mobs_to_pick_from
	var/prob_fall = 0
	var/prob_spawn = 0
	var/atmos_comp = TRUE
	var/interactable = TRUE
	var/annihilate_bounds = TRUE

/datum/map_template/dynamic_overmap/proc/update_lighting(turf/T)
	return

// Map z-level base (referenced as associated_map_datum target).
/datum/map_z_level

/datum/map_z_level/common_lateload

/datum/map_z_level/common_lateload/New(map, z)
	return

// /obj/machinery/gateway stub — was defined in awaymissions/gateway.dm.
// Referenced by cryopod/energy_ball iterators; presence-only checks. Keeping
// as a stub avoids deleting consumer code blocks.
/obj/machinery/gateway

// NOTE: /obj/tether_away_spawner is no longer stubbed here — it was a vars-only
// stub that silently disabled the spawners live submaps still place. The real
// implementation (Initialize + process) now lives in
// code/modules/awaymissions/tether_away_spawner.dm.
