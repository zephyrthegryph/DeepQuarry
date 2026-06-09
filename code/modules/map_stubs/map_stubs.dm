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
