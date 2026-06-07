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

// Engine template — was defined in southern_cross _engine_submaps.dm.
// Referenced by code/controllers/subsystems/mapping.dm (active subsystem).
/datum/map_template/engine

// Dynamic overmap template — was defined in modular_chomp/maps/overmap/space_pois/space_pois.dm.
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

// Engine loader landmark — was defined in the same engine submap file.
/obj/effect/landmark/engine_loader

/obj/effect/landmark/engine_loader/proc/annihilate_bounds()
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

// Tether away spawner — was defined in maps/offmap_vr/common_offmaps.dm.
// Subtypes in maps/common/common_things.dm reference its vars.
/obj/tether_away_spawner
	name = "RENAME ME, JERK"
	icon_state = "x"
	invisibility = INVISIBILITY_ABSTRACT
	mouse_opacity = 0
	density = 0
	anchored = 1
	var/list/mobs_to_pick_from
	var/prob_spawn = 100
	var/prob_fall = 5
	var/faction
	var/atmos_comp
	var/mob/living/simple_mob/my_mob
	var/depleted = FALSE
