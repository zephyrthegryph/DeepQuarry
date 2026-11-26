// /tg/ vendor compat layer for LINDA atmos.
//
// The vendored LINDA atmos files (SSair, LINDA_*, reactions, gas_mixture)
// reference /tg/-side infrastructure (var declarations, GLOB lists, helper
// procs, /atom base hooks) that CHOMP doesn't natively provide. Rather than
// modify the vendored files, this layer declares the surface they expect.
//
// Each entry is either:
//   - a real implementation bridging to a CHOMP-side equivalent
//     (freeze_turf → CHOMP wet_floor)
//   - a real base no-op for a /tg/ hook that subtypes override
//     (process_atmos, apply_fire_protection)
//   - a var/list scaffold (multiz_levels, z_list, electrolyzer_reactions)
//
// CHOMP atmos MACHINERY (vents, scrubbers, pipes, canisters, alarms) is
// in code/domains/atmos/ and code/content/machinery/atmoalter/ — do not
// add machinery declarations here.

// === SSblackbox: kept as a system for the boot-order tests; nothing records through it ===
SYSTEM_DEF(blackbox)
	name = "Blackbox"
	// Feedback-recording compat shim only: no periodic work, nothing to boot.
	var/sealed = FALSE




// === /tg/ globals SSair expects ===
GLOBAL_LIST_INIT(contrast_colors, list("#ff0000", "#00ff00", "#0000ff", "#ffff00", "#00ffff", "#ff00ff"))


// === /tg/-specific vars on /obj/machinery and /obj/item ===
// === /tg/ hud + debug viz ===
/datum/hud
	var/atmos_debug_overlays

// /obj/effect/abstract/atmos_aware deleted — had zero callers.

/obj/effect/overlay/atmos_excited
	icon = null
	mouse_opacity = 0


// === /datum/atmosphere (planet atmosphere descriptor) ===
/datum/atmosphere
	var/id
	var/gas_string = ""
	var/temperature = T20C

// === SSmapping multi-z helpers (CHOMP doesn't expose these as GLOB lists) ===
/datum/system/mapping
	var/list/z_list = list() // subsystem singleton; one entry per z-level
	var/max_plane_offset = 0
	var/list/multiz_levels = list() // subsystem singleton; one entry per z-level


// === Per-z-level metadata ===
/datum/space_level
	var/list/traits = list() // ALLOW(instance_list): d: every z-level has traits


/// Whether SSair.setup_allturfs registers this turf's air at round start.
/turf/var/init_air = TRUE


// === /tg/ looping_sound extra vars (LINDA fire ambience uses these) ===
/datum/looping_sound
	var/falloff_distance = 0
	var/atom/parent


// === Heat→color helpers for fire visual gradient ===
/proc/heat2colour_r(temp)
	if(temp < 1000)
		return 64
	if(temp < 2500)
		return min(255, 64 + (temp - 1000) * 191 / 1500)
	return 255

/proc/heat2colour_g(temp)
	if(temp < 1500)
		return 32
	return min(200, 32 + (temp - 1500) * 168 / 2000)

/proc/heat2colour_b(temp)
	if(temp < 3000)
		return 0
	return min(150, (temp - 3000) * 150 / 1500)


// === /tg/ direction setter (the LINDA fire and the draw tests still call it) ===
/atom/proc/setDir(new_dir)
	set_dir(new_dir)


// SSair admin TGUI procs override the fork's tgui_state/tgui_interact/tgui_data/
// tgui_act base (code/modules/tgui/external.dm) directly on
// /datum/system/air in the vendored SSair.dm — no stubs needed here.


// get_rebuild_targets — used to be needed by /tg/'s centralized pipenet
// rebuild subsystem; removed when we dropped that subsystem in favour of
// CHOMP's per-machine build_network(). No callers remain.


// /atom.CanZASPass — real impl lives in xgm_compat.dm (routes to can_atmos_pass
// so CHOMP overrides on doors/windows/airlocks influence LINDA adjacency).


// /turf/proc/apply_fire_protection — flame-retardant tiles call this to mark
// themselves as fire-resistant for a short window (firefoam, fire extinguisher
// spray). Sets a per-turf cooldown that hotspot_expose checks before igniting.
#define FIRE_PROTECTION_DURATION (30 SECONDS)
/turf
	var/fire_protection = 0

/turf/proc/apply_fire_protection()
	STAMP(src, fire_protection, CLOCK_WORLD)


// Structured scan data shared by PDA, pAI and communicator TGUI clients.
// Keep this separate from atmosanalyzer_scan(): that proc deliberately returns
// chat-ready HTML strings, while these clients consume typed rows.
/proc/get_gas_mixture_default_scan_data(datum/gas_mixture/air)
	if(!air)
		return list()
	var/list/output = list()
	var/pressure = air.return_pressure()
	output += list(list(
		"entry" = "Pressure",
		"val" = round(pressure, 0.1),
		"units" = " kPa",
		"bad_low" = 20,
		"poor_low" = 80,
		"poor_high" = 120,
		"bad_high" = 300
	))
	var/total_moles = air.total_moles()
	if(total_moles > 0)
		for(var/gas_id in air.gas_ids())
			var/percentage = round((LINDA_GAS_AMT(air, gas_id) / total_moles) * 100, 0.1)
			var/is_oxygen = gas_id == GAS_O2
			output += list(list(
				"entry" = GLOB.gas_data.name[gas_id] || "Unknown gas",
				"val" = percentage,
				"units" = "%",
				"bad_low" = is_oxygen ? 16 : -1,
				"poor_low" = is_oxygen ? 19 : -1,
				"poor_high" = is_oxygen ? 24 : 5,
				"bad_high" = is_oxygen ? 30 : 20
			))
	output += list(list(
		"entry" = "Temperature",
		"val" = round(air.return_temperature() - T0C, 0.1),
		"units" = "&deg;C",
		"bad_low" = -100,
		"poor_low" = 10,
		"poor_high" = 40,
		"bad_high" = 100
	))
	return output


// === /datum/gas_mixture/proc/get_thermal_energy_change ===
/datum/gas_mixture/proc/get_thermal_energy_change(new_temperature)
	return heat_capacity() * (new_temperature - return_temperature())


// /tg/'s electrolyzer scaffolding (GLOB.electrolyzer_reactions, /datum/
// electrolyzer_reaction) was removed alongside /datum/gas_mixture/proc/
// electrolyze in gasmixtures/gas_mixture.dm — DQ has no electrolyzer
// machinery to populate or consume them.



// === /atom/movable move_resist (lazy state field, code/datums/sparse_vars/movable_misc.dm) + force defines ===

#define MOVE_FORCE_DEFAULT 50
#define MOVE_FORCE_PUSH_RATIO 1
#define MOVE_FORCE_FORCEPUSH_RATIO 1


// === Multi-z helpers ===

GLOBAL_LIST_INIT(cardinals_multiz, list(NORTH, SOUTH, EAST, WEST, UP, DOWN))
GLOBAL_LIST_INIT(diagonals_multiz, list(NORTHEAST, NORTHWEST, SOUTHEAST, SOUTHWEST, UP|NORTH, UP|SOUTH, UP|EAST, UP|WEST, DOWN|NORTH, DOWN|SOUTH, DOWN|EAST, DOWN|WEST))

/proc/get_step_multiz(atom/source, direction)
	if(direction == UP)
		return GetAbove(source)
	if(direction == DOWN)
		return GetBelow(source)
	return get_step(source, direction)

/proc/get_dir_multiz(atom/source, atom/target)
	if(!source || !target)
		return 0
	if(source.z != target.z)
		return source.z < target.z ? UP : DOWN
	return get_dir(source, target)


// === /turf zAir / atmos_expose hooks LINDA expects ===
// Vertical atmos gate for multi-z: /turf/open/air_block_mask (LINDA_system.dm)
// blocks a turf's UP/DOWN face unless air may both leave and enter through it.
// These MUST NOT be blanket-TRUE: on a stacked-deck station every solid floor
// would then atmos-merge with the tile directly above/below it THROUGH the
// floor, so any deck tile overhanging space vents to vacuum forever (this was
// the Southern Cross SSair-starvation churn — ~573 perpetual vents from the
// atmos gas tanks on deck 2 leaking down into the deck-1 space beneath them).
// Air only crosses a z-boundary through an actual opening: a /turf/simulated/open
// (openspace) tile — i.e. the UPPER turf of the vertical pair must be the hole.
// (istype instead of the isopenspace() macro: this compat file parses before
// is_helpers.dm in the .dme, so the macro isn't defined yet here.)
/// Whether this turf is a hole air falls through (openspace): its floor, its DOWN face, lets air pass. Type data, read by
/// the Rust atmos core when it registers the map's turfs (vg_hook_register_world_turfs()), so DM asks nothing per turf.
/turf/var/air_z_open = FALSE
/turf/simulated/open/air_z_open = TRUE

/turf/proc/zAirIn(direction, turf/source)
	// Air rises UP into src from below only if src itself is a hole (no floor).
	if(direction & UP)
		return air_z_open
	return TRUE

/turf/proc/zAirOut(direction, turf/source)
	// Air falls DOWN out of src's bottom only if src itself is a hole (no floor).
	if(direction & DOWN)
		return air_z_open
	return TRUE

// /turf/proc/freeze_turf — called by the water_vapor reaction when ambient
// temperature is below the deposition point. Marks the turf as iced over so
// movement code can apply slip behaviour, and consumes a moles_visible of
// water vapor from the reacting mix.
/turf/proc/freeze_turf()
	return FALSE

/turf/simulated/freeze_turf()
	if(wet >= TURFSLIP_ICE)
		return FALSE
	wet_floor(TURFSLIP_ICE)
	return TRUE

// /obj/item/stack/sheet doesn't exist on this fork (CHOMP uses
// /obj/item/stack/material for sheets). Declare /obj/item/stack/sheet as a
// thin shell parent so /tg/-shaped paths like /obj/item/stack/sheet/hot_ice
// resolve, and give hot_ice a real (not "stub") item so the freon-cooling
// reaction (gasmixtures/reactions.dm:427) produces a usable stackable sheet.
/obj/item/stack/sheet
	gender = NEUTER
	max_amount = 50
	w_class = ITEMSIZE_NORMAL

/obj/item/stack/sheet/hot_ice
	name = "hot ice"
	desc = "Frozen oxygen and plasma. Cold to the touch."
	singular_name = "hot ice sheet"
	icon = 'icons/obj/stacks.dmi'
	icon_state = "sheet-metal"  // placeholder; no dedicated hot_ice sprite on this fork

// /atom/proc/process_atmos removed alongside SSair.atmos_machinery.
// /atom/proc/process_exposure removed alongside SSair.atom_process.

