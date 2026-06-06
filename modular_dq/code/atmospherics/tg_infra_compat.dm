// /tg/ vendor compat layer for LINDA atmos.
//
// The vendored LINDA atmos files (SSair, LINDA_*, reactions, gas_mixture)
// reference /tg/-side infrastructure (var declarations, GLOB lists, helper
// procs, /atom base hooks) that CHOMP doesn't natively provide. Rather than
// modify the vendored files, this layer declares the surface they expect.
//
// Each entry is either:
//   - a real implementation bridging to a CHOMP-side equivalent
//     (record_feedback → feedback_add_details, wet_floor → CHOMP wet_floor,
//      analyze_gases, fire_nuclear_particle → SSradiation.irradiate)
//   - a real base no-op for a /tg/ hook that subtypes override
//     (Initalize_Atmos, atmos_expose, process_atmos, apply_fire_protection)
//   - a var/list scaffold (multiz_levels, z_list, electrolyzer_reactions)
//
// CHOMP atmos MACHINERY (vents, scrubbers, pipes, canisters, alarms) is
// restored in code/ATMOSPHERICS/ and code/game/machinery/atmoalter/ — do not
// add machinery declarations here.

// === /tg/ subsystem flags ===
/datum/controller/subsystem
	var/ss_flags = 0




// === /tg/ SSblackbox telemetry — wired to CHOMP's feedback_add_details ===
/datum/controller/subsystem/blackbox
	var/sealed = FALSE

/datum/controller/subsystem/blackbox/proc/record_feedback(key_type, key_name, increment_by = 1, data = null)
	if(!GLOB.blackbox)
		return
	var/value = !isnull(data) ? "[data]" : "[increment_by]"
	feedback_add_details(key_name, "[key_type]:[value]")

var/global/datum/controller/subsystem/blackbox/SSblackbox = new()


// === /tg/ globals SSair expects ===
GLOBAL_LIST_EMPTY(active_turfs_startlist)
GLOBAL_LIST_INIT(contrast_colors, list("#ff0000", "#00ff00", "#0000ff", "#ffff00", "#00ffff", "#ff00ff"))


// === /tg/-specific vars on /obj/machinery and /obj/item ===
// DQEdit — atmos_processing removed alongside SSair.atmos_machinery.
/obj/machinery
	var/rebuilding = FALSE

/obj/item
	var/datum/gas_mixture/air_temporary


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
	var/base_gases
	var/gas_string = ""
	var/temperature = T20C

/datum/atmosphere/proc/return_gas_string()
	return ""


// === SSmapping multi-z helpers (CHOMP doesn't expose these as GLOB lists) ===
/datum/controller/subsystem/mapping
	var/list/z_list = list()
	var/max_plane_offset = 0
	var/list/multiz_levels = list()


// === Per-z-level metadata ===
/datum/space_level
	var/list/traits = list()


// flags_1 declaration moved to modular_dq/code/atmospherics/atom_flags_1.dm so
// /atom/Initialize sets INITIALIZED_1 properly (was a dead zero stub).
//
// requires_activation and the base /turf/proc/Initalize_Atmos are kept here:
// requires_activation is set by add_to_active's fall-through; the base
// Initalize_Atmos is a legitimate no-op for /turf base (only /turf/open
// participates in atmos). /turf/open/Initalize_Atmos in dq_linda_turf_air.dm
// is the real implementation that builds adjacency.
/turf/var/requires_activation = FALSE
/turf/var/init_air = TRUE
/turf/proc/Initalize_Atmos(times_fired)
	return


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


// === /tg/ smoothing junction stubs ===
/atom/proc/setDir(new_dir)
	dir = new_dir

/atom
	var/smoothing_junction = 0

/atom/proc/set_smoothed_icon_state(new_junction)
	smoothing_junction = new_junction


// SSair admin TGUI procs (ui_state/ui_interact/ui_data/ui_act) are declared
// directly on /datum/controller/subsystem/air in the vendored SSair.dm — no
// stubs needed here. (Previously kept as base declarations because SSair.dm
// used override syntax; promoted to fresh declarations in SSair.dm.)


// get_rebuild_targets — used to be needed by /tg/'s centralized pipenet
// rebuild subsystem; removed when we dropped that subsystem in favour of
// CHOMP's per-machine build_network(). No callers remain.


// /atom.CanZASPass — real impl lives in xgm_compat.dm (routes to can_atmos_pass
// so CHOMP overrides on doors/windows/airlocks influence LINDA adjacency).


// /turf/proc/apply_fire_protection — flame-retardant tiles call this to mark
// themselves as fire-resistant for a short window (firefoam, fire extinguisher
// spray). Sets a per-turf cooldown that hotspot_expose checks before igniting.
#define FIRE_PROTECTION_DURATION (30 SECONDS)
/turf/var/fire_protection = 0

/turf/proc/apply_fire_protection()
	fire_protection = world.time


// /proc/get_gas_mixture_default_scan_data — used by /tg/'s gas analyzer to
// build the default scan readout. CHOMP atmosanalyzer_scan in
// code/_helpers/atmospherics.dm already does this; just route through.
/proc/get_gas_mixture_default_scan_data(datum/gas_mixture/air)
	if(!air)
		return null
	return atmosanalyzer_scan(null, air, null)


// === /datum/gas_mixture/proc/get_thermal_energy_change ===
/datum/gas_mixture/proc/get_thermal_energy_change(new_temperature)
	return heat_capacity() * (new_temperature - temperature)


// /tg/'s electrolyzer scaffolding (GLOB.electrolyzer_reactions, /datum/
// electrolyzer_reaction) was removed alongside /datum/gas_mixture/proc/
// electrolyze in gasmixtures/gas_mixture.dm — DQ has no electrolyzer
// machinery to populate or consume them.


// atmosanalyzer_scan + analyze_gases live in code/_helpers/atmospherics.dm.
/proc/analyze_gases(obj/source, mob/user)
	if(!source || !user)
		return
	var/datum/gas_mixture/air = isturf(source) ? source.return_air() : (source.loc?.return_air())
	if(!air)
		to_chat(user, span_warning("No atmospheric readings available."))
		return
	for(var/line in atmosanalyzer_scan(source, air, user))
		to_chat(user, line)


// === /atom/movable move_resist + force defines ===
/atom/movable
	var/move_resist = 100

#define MOVE_FORCE_DEFAULT 50
#define MOVE_FORCE_PUSH_RATIO 1
#define MOVE_FORCE_FORCEPUSH_RATIO 1


// === Multi-z helpers ===
#define GET_Z_PLANE_OFFSET(z) 0
#define cardinals cardinal

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
/turf/proc/zAirIn(direction, turf/source)
	return TRUE

/turf/proc/zAirOut(direction, turf/source)
	return TRUE

// atmos_expose / should_atmos_process — base /turf no-ops are FALSE/return;
// real impls on /turf/simulated live in LINDA_turf_tile.dm. The full call
// chain runs through /turf/open/temperature_expose.
/turf/proc/atmos_expose(datum/gas_mixture/air, temperature)
	return

/turf/proc/should_atmos_process(datum/gas_mixture/air, exposed_temperature)
	return FALSE

// DQEdit — /turf/proc/check_atmos_process removed; was a no-op that swallowed
// the temperature_expose handoff. Caller in LINDA_turf_tile.dm now calls
// should_atmos_process + atmos_expose directly.

/turf/proc/return_analyzable_air()
	return return_air()

// /turf/proc/Melt — called by /turf/simulated/burn_turf() when a tile has
// been heat-soaked past its survival threshold. Replaces the turf with the
// CHOMP "burned down" form: walls become plating, floors become plating,
// plating itself dissolves to space. Other turfs no-op.
/turf/proc/Melt()
	return

/turf/simulated/wall/Melt()
	// CHOMP /turf/simulated/wall has its own lowercase melt() for the wall-
	// collapses-into-floor flow; defer to it so wall-specific bookkeeping runs.
	melt()

/turf/simulated/floor/Melt()
	if(istype(src, /turf/simulated/floor/plating))
		return
	ChangeTurf(/turf/simulated/floor/plating, preserve_outdoors = TRUE)

/turf/simulated/floor/plating/Melt()
	// Plating burned beyond plating: open to the deck below. ChangeTurf to
	// space if there's no floor underneath, otherwise leave it as plating
	// since there's nothing thinner.
	if(GetBelow(src))
		ChangeTurf(/turf/simulated/open, preserve_outdoors = TRUE)
	else
		ChangeTurf(/turf/space, preserve_outdoors = TRUE)


// DQEdit — /datum/component/wet_floor + TURF_WET_PERMAFROST removed alongside
// the matching branch in gasmixtures/reactions.dm. CHOMP keeps wetness on
// /turf/simulated.wet directly; no component-based tracking.

/turf/proc/water_vapor_gas_act()
	if(istype(src, /turf/space) || istype(src, /turf/simulated/open))
		return FALSE
	if(istype(src, /turf/simulated))
		var/turf/simulated/S = src
		if(hascall(S, "wet_floor"))
			S.wet_floor()
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

/turf/proc/fire_nuclear_particle()
	if(SSradiation)
		SSradiation.irradiate(src, 50)
	return

/proc/isgroundlessturf(turf/T)
	return istype(T, /turf/space) || istype(T, /turf/simulated/open)

/proc/isnoslipturf(turf/T)
	if(!T)
		return FALSE
	return TRUE

/proc/visible_hallucination_pulse(atom/center, range, hallucination_amount, duration)
	if(!center || !range)
		return
	for(var/mob/living/carbon/human/H in range(range, center))
		if(H.species && (H.species.flags & (NO_POISON | IS_PLANT | NO_HALLUCINATION)))
			continue
		H.hallucination = max(H.hallucination, (hallucination_amount || 10))
	return

// DQEdit — /tg/'s vendored reactions reference foam types in this tree
// (halon-combustion resin is the live caller; gasmixtures/reactions.dm:897).
// Declared as thin marker types so type paths resolve at compile; do_foam
// ignores the foam_type arg and always spawns CHOMP's /obj/effect/effect/foam.
/datum/effect_system/fluid_spread/foam
/datum/effect_system/fluid_spread/foam/metal/resin/halon

// /tg/'s vendored reactions call do_foam with named args
// (amount, holder, location, foam_type). The fork doesn't implement the
// /tg/ foam tree, so foam_type is ignored — every call spawns CHOMP's
// /obj/effect/effect/foam. holder is accepted to match the call shape.
/proc/do_foam(amount, holder, location, foam_type)
	if(!location || !amount)
		return
	for(var/i in 1 to min(amount, 10))
		new /obj/effect/effect/foam(get_turf(location))
	return

// DQEdit — /obj/item/stack/sheet doesn't exist on this fork (CHOMP uses
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

// DQEdit — /atom/proc/process_atmos removed alongside SSair.atmos_machinery.
// DQEdit — /atom/proc/process_exposure removed alongside SSair.atom_process.
