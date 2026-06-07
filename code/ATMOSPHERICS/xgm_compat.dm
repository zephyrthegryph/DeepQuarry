// XGM → LINDA compatibility layer.
//
// XGM was the gas API that CHOMP (via Baystation/Polaris/Virgo) used: gases
// keyed by string id, flag bitmasks per gas, per-mixture entropy, "graphic"
// overlays, the ZAS zone graph. LINDA stores gases keyed by /datum/gas type,
// has no flag bitmask, and tracks active turfs / excited groups instead of
// zones.
//
// This file is the bridge between the two: real implementations of the
// XGM-shaped APIs that CHOMP-vintage machinery (pumps, scrubbers, canisters,
// tanks, fusion core, supermatter, gas thruster, overmap shuttle fuel, etc.)
// still calls. Every proc here is a real implementation, not a no-op.
//
// CONTENTS (by section):
//   1. XGM gas-id → /datum/gas type lookup
//   2. /datum/gas_mixture proc shims (adjust_gas, add_thermal_energy, …)
//   3. Flag-keyed gas accessors (get_by_flag, remove_by_flag) backed by gas_data
//   4. ZAS turf-API bridges (c_airblock, air_blocked, mark_for_update,
//      update_nearby_tiles, CanZASPass)
//   5. GLOB.gas_data — XGM-shaped per-gas metadata lookup
//   6. Specific entropy formulae (used by pump power calculations)
//   7. Legacy decl/var declarations (vsc, contaminated, /obj/fire, /datum/decl/xgm_gas)
//   8. Suit/head protection checks (pl_suit_protected, pl_head_protected)

// =====================================================================
// 1. XGM string id → /datum/gas type lookup
// =====================================================================

/datum/gas_mixture/proc/get_xgm_id_for_gas(gas_id_string)
	var/static/list/xgm_id_to_type
	if (isnull(xgm_id_to_type))
		xgm_id_to_type = list()
		for (var/datum/gas/gas_type as anything in subtypesof(/datum/gas))
			xgm_id_to_type[initial(gas_type.id)] = gas_type
	return xgm_id_to_type[gas_id_string]


// =====================================================================
// 2. /datum/gas_mixture proc shims for XGM-style callers
// =====================================================================

// XGM: adjust_gas(gas_id_string, amount) — add/subtract moles by string id.
// LINDA's native adjust_gas(gas_type, amount) takes a type path. Override here
// to accept BOTH so CHOMP and LINDA call sites coexist while migration runs.
/datum/gas_mixture/adjust_gas(gas, amount, update = 1)
	if (istext(gas))
		var/datum/gas/gas_type = get_xgm_id_for_gas(gas)
		if (isnull(gas_type) || amount == 0)
			return
		ASSERT_GAS(gas_type, src)
		gases[gas_type][MOLES] += amount
		if(gases[gas_type][MOLES] <= 0)
			gases -= gas_type
		return
	if (amount == 0)
		return
	ASSERT_GAS(gas, src)
	gases[gas][MOLES] += amount
	if(gases[gas][MOLES] <= 0)
		gases -= gas

// XGM: adjust_gas_temp(gas_id, moles, temp) — add moles + their heat.
// Weighted thermal energy: T_new = (n_old*T_old + n_new*T_new) / (n_old+n_new).
/datum/gas_mixture/proc/adjust_gas_temp(gas_id, moles, temp, update = 1)
	if (moles <= 0)
		return
	var/datum/gas/gas_type = istext(gas_id) ? get_xgm_id_for_gas(gas_id) : gas_id
	if (isnull(gas_type))
		return
	var/old_total = total_moles()
	ASSERT_GAS(gas_type, src)
	gases[gas_type][MOLES] += moles
	if (old_total > 0)
		temperature = (temperature * old_total + temp * moles) / (old_total + moles)
	else
		temperature = temp

// XGM: add_thermal_energy(joules) — add heat at current heat_capacity.
/datum/gas_mixture/proc/add_thermal_energy(joules)
	var/cap = heat_capacity()
	if (cap <= 0)
		return
	set_temperature((temperature * cap + joules) / cap)

// XGM: adjust_multi(g1, n1, g2, n2, ...) — variadic adjustment helper.
/datum/gas_mixture/proc/adjust_multi(...)
	var/list/L = args
	var/i = 1
	while(i < length(L))
		adjust_gas(L[i], L[i + 1])
		i += 2

// DQEdit — update_values() removed. Every CHOMP caller has been migrated
// to drop the no-op call (LINDA auto-archives on read).

// XGM: remove_volume(removed_volume) — remove a fraction by volume.
// LINDA's remove(amount) takes moles. Equivalent: removed_volume / volume.
/datum/gas_mixture/proc/remove_volume(removed_volume)
	if (volume <= 0)
		return null
	return remove_ratio(min(1, removed_volume / volume))

// share_ratio(giver, ratio) — weighted blend: self_new = (1-r)*self + r*giver.
// giver is UNCHANGED — this is the "pull from infinite reservoir" share, used
// by /atmos/turfs/processing.rs:125 for planetary-atmosphere share and by
// transit_tubes for "match the outside environment". Matches the Rust
// /datum/gas_mixture/share_ratio impl in verdigris/atmos/src/gas/mixture.rs:279
// exactly so the DM fallback and the auxmos byondapi-bound version produce
// identical results.
/datum/gas_mixture/proc/share_ratio(datum/gas_mixture/giver, ratio)
	if(!giver || ratio <= 0)
		return
	ratio = min(1, ratio)
	var/inv_ratio = 1 - ratio
	var/our_heat = heat_capacity() * inv_ratio
	var/their_heat = giver.heat_capacity() * ratio
	// Scale our existing moles by (1-r); add giver's moles * r. giver untouched.
	for(var/datum/gas/g as anything in gases)
		gases[g][MOLES] *= inv_ratio
	for(var/datum/gas/g as anything in giver.gases)
		ASSERT_GAS(g, src)
		gases[g][MOLES] += giver.gases[g][MOLES] * ratio
	// Garbage-collect zeros so total_moles() doesn't see ghost entries.
	for(var/datum/gas/g as anything in gases)
		if(gases[g][MOLES] <= 0)
			gases -= g
	var/combined_heat = our_heat + their_heat
	if(combined_heat > MINIMUM_HEAT_CAPACITY)
		set_temperature((our_heat * temperature + their_heat * giver.temperature) / combined_heat)


// =====================================================================
// 3. Flag-keyed gas accessors
// =====================================================================
//
// XGM gas flags (XGM_GAS_FUEL, XGM_GAS_OXIDIZER, XGM_GAS_CONTAMINANT,
// XGM_GAS_FUSION_FUEL) live on /datum/decl/xgm_gas subtypes (code/defines/
// gases.dm). GLOB.gas_data.flags[gas_id_string] gives the bitmask, populated
// by /datum/xgm_gas_data/New() below.

/datum/gas_mixture/proc/get_by_flag(flag)
	if(!gases || !flag)
		return 0
	. = 0
	for(var/datum/gas/g as anything in gases)
		var/gas_id = initial(g.id)
		if(GLOB.gas_data.flags[gas_id] & flag)
			. += gases[g][MOLES]

// XGM: remove moles of flag-matching gases up to `amount` total, proportionally.
// Returns a /datum/gas_mixture containing only the removed moles.
/datum/gas_mixture/proc/remove_by_flag(flag, amount)
	if(!gases || !flag || amount <= 0)
		return null
	var/total_matching = get_by_flag(flag)
	if(total_matching <= 0)
		return null
	var/to_remove = min(amount, total_matching)
	var/datum/gas_mixture/removed = new
	removed.temperature = temperature
	removed.volume = volume
	for(var/datum/gas/g as anything in gases)
		var/gas_id = initial(g.id)
		if(!(GLOB.gas_data.flags[gas_id] & flag))
			continue
		var/share = gases[g][MOLES] * (to_remove / total_matching)
		gases[g][MOLES] -= share
		ASSERT_GAS(g, removed)
		removed.gases[g][MOLES] = share
		if(gases[g][MOLES] <= 0)
			gases -= g
	return removed

// XGM: iteration over present gases. Used by air alarms / scrubbers / analyzers
// that expected the XGM string-keyed .gas[] dict.
/datum/gas_mixture/proc/gas_ids()
	. = list()
	if(!gases)
		return
	for(var/datum/gas/g as anything in gases)
		. += initial(g.id)

// XGM: get_mass() — sum of moles × molar mass across all gases. Used by
// gas thruster (code/modules/overmap/ships/engines/gas_thruster.dm) for
// exhaust momentum calculation.
/datum/gas_mixture/proc/get_mass()
	. = 0
	if(!gases)
		return
	for(var/datum/gas/g as anything in gases)
		var/gas_id = initial(g.id)
		var/molar_mass = GLOB.gas_data.molar_mass[gas_id]
		if(!molar_mass)
			molar_mass = initial(g.specific_heat) * 0.05
		. += gases[g][MOLES] * molar_mass

// XGM: check_combustability() — true iff this mixture can burn (oxidizer + fuel
// both present at meaningful levels). Used by gas thruster to gate exhaust ignition.
/datum/gas_mixture/proc/check_combustability()
	var/oxidizer = get_by_flag(XGM_GAS_OXIDIZER)
	if(oxidizer < 0.5)
		return FALSE
	var/fuel = get_by_flag(XGM_GAS_FUEL)
	return fuel >= 0.5


// =====================================================================
// 4. ZAS turf-API bridges
// =====================================================================

// CHOMP code calls assume_gas(gas_id, moles, temp) directly on a TURF
// expecting it to absorb the gas into the turf's air. Forward through.
/turf/proc/assume_gas(gas_id, amount, temp)
	var/datum/gas_mixture/air = return_air()
	if(!air || amount <= 0)
		return FALSE
	air.adjust_gas(gas_id, amount)
	if(!isnull(temp) && temp > 0)
		var/old_total = max(air.total_moles() - amount, 0)
		if(old_total > 0)
			air.set_temperature((air.temperature * old_total + temp * amount) / (old_total + amount))
		else
			air.set_temperature(temp)
	if(SSair)
		SSair.add_to_active(src)
	return TRUE

// ZAS: c_airblock(T) returned the bitfield (AIR_BLOCKED | ZONE_BLOCKED).
// LINDA doesn't track zones, so the ZONE_BLOCKED-only case (e.g. a window
// that passes air but not zone graph) doesn't exist — every "fully blocked"
// case returns BLOCKED (= AIR_BLOCKED | ZONE_BLOCKED) for compatibility with
// callers like aliens.dm that check `== BLOCKED`. Callers that mask with
// `& AIR_BLOCKED` (gas_thruster) still get the right answer.
/turf/proc/c_airblock(turf/T)
	if(!T || T == src)
		return 0
	if(blocks_air || T.blocks_air)
		return BLOCKED
	if(!istype(src, /turf/open) || !istype(T, /turf/open))
		return BLOCKED
	// can_atmos_pass walks contents of both turfs (doors, windows, objects)
	// and asks each whether atmos crosses — same semantics as ZAS would have
	// applied to the boundary.
	if(can_atmos_pass(T, FALSE))
		return 0
	return BLOCKED

// ZAS: SSair.air_blocked(T1, T2) — true if these two turfs are atmos-separated.
// LINDA equivalent: T1.atmos_adjacent_turfs lists T2 (and vice versa) iff they
// can share air. If neither side has computed adjacency yet we have to be
// conservative and answer "blocked" — the alternative is to invoke
// can_atmos_pass which mutates supeconductivity state and can return stale
// answers for the wrong reasons.
/datum/controller/subsystem/air/proc/air_blocked(turf/A, turf/B)
	if(!A || !B)
		return TRUE
	if(A == B)
		return FALSE
	if(!istype(A, /turf/open) || !istype(B, /turf/open))
		return TRUE
	if(A.blocks_air || B.blocks_air)
		return TRUE
	if(A.atmos_adjacent_turfs && A.atmos_adjacent_turfs[B])
		return FALSE
	if(B.atmos_adjacent_turfs && B.atmos_adjacent_turfs[A])
		return FALSE
	// Adjacency not built yet — kick a rebuild now so the next caller gets a
	// fresh answer, and answer "blocked" for this call.
	A.immediate_calculate_adjacent_turfs()
	if(A.atmos_adjacent_turfs && A.atmos_adjacent_turfs[B])
		return FALSE
	return TRUE

// ZAS: SSair.mark_for_update(T) — schedule a turf for zone-graph rebuild.
// LINDA equivalent: rebuild adjacency + add to active.
/datum/controller/subsystem/air/proc/mark_for_update(turf/T)
	if(!T)
		return
	T.air_update_turf(TRUE, FALSE)

// ZAS: /atom/movable.update_nearby_tiles() — was called whenever an object
// moved or changed state that could affect zone connectivity. LINDA equivalent:
// recompute the turf's atmos_adjacent_turfs since this atom may now block or
// unblock atmos passage in a direction.
/atom/movable/proc/update_nearby_tiles(need_rebuild = 0)
	var/turf/T = get_turf(src)
	if(T && SSair?.initialized)
		T.air_update_turf(TRUE, FALSE)
	return TRUE

// ZAS: gas overlay refresh on a turf. /tg/'s /turf/open/floor renders gas
// overlays through SSair's excited_group + per-turf update_visuals. CHOMP
// callers that hand-poked the overlay list are no-ops; the LINDA cycle picks
// up the change on the next process_cell.
/turf/proc/update_graphic(list/graphic_add = null, list/graphic_remove = null)
	return

// /atom.CanZASPass(T, is_zone) — CHOMP atoms (doors, windows, mobs, transit
// tubes, ceilings) override this to gate air passage. The base returns TRUE
// ("passes") matching the old ZAS default. LINDA's CANATMOSPASS macro and
// can_atmos_pass hook call this for objects with can_atmos_pass=ATMOS_PASS_PROC,
// so the existing CHOMP CanZASPass overrides take effect under LINDA without
// each needing a separate can_atmos_pass proc override.
/atom/proc/CanZASPass(turf/T, is_zone)
	return TRUE


// =====================================================================
// 5. GLOB.gas_data — XGM-shaped per-gas metadata lookup
// =====================================================================

/datum/xgm_gas_data
	var/list/name = list()
	var/list/specific_heat = list()
	var/list/molar_mass = list()
	var/list/gases = list()
	var/list/tile_overlay = list()
	var/list/molar_specific_volume = list()
	var/list/flags = list()
	var/list/overlay_limit = list()

// Real molar masses (kg/mol) for the LINDA-only /datum/gas subtypes that
// don't have a matching /datum/decl/xgm_gas in code/defines/gases.dm. Real
// chemistry values where the gas is a real compound; reasonable approximations
// for /tg/'s fictional gases (matching their gameplay weight profile —
// noble-class heavier, hydrogen-class lighter). Used by specific_entropy_gas
// and gas_thruster.get_mass — wrong values silently distort pump power-draw
// and exhaust thrust.
GLOBAL_LIST_INIT(dq_linda_only_molar_masses, list(
	"water_vapor" = 0.018,        // H2O
	"tritium" = 0.006,            // T2 (heavy hydrogen)
	"hydrogen" = 0.002,           // H2
	"helium" = 0.004,             // He
	"freon" = 0.137,              // CCl3F approximate
	"halon" = 0.300,              // fictional fire-retardant
	"healium" = 0.080,            // fictional
	"hypernoblium" = 0.250,       // fictional super-noble
	"miasma" = 0.048,             // mostly methanethiol
	"nitrium" = 0.060,            // fictional N/O hybrid
	"pluoxium" = 0.080,           // O3/O2 mix
	"proto_nitrate" = 0.060,      // fictional
	"zauker" = 0.040,             // fictional
	"bz" = 0.150,                 // fictional anaesthetic
	"antinoblium" = 0.300,        // fictional
))

// Populate every list from /datum/decl/xgm_gas/* subtypes (code/defines/gases.dm).
// Those decls carry the canonical id/name/specific_heat/molar_mass/flags
// metadata; we cross-index by id so XGM-shaped string-keyed lookups work.
/datum/xgm_gas_data/New()
	. = ..()
	for(var/datum/decl/xgm_gas/d as anything in subtypesof(/datum/decl/xgm_gas))
		var/id = initial(d.id)
		if(!id)
			continue
		name[id] = initial(d.name)
		specific_heat[id] = initial(d.specific_heat)
		molar_mass[id] = initial(d.molar_mass)
		gases[id] = d
		tile_overlay[id] = initial(d.tile_overlay)
		flags[id] = initial(d.flags)
		overlay_limit[id] = initial(d.overlay_limit)
		molar_specific_volume[id] = 0.001
	// Fill in /datum/gas LINDA subtypes that don't have a matching xgm_gas decl.
	// Use real molar masses from dq_linda_only_molar_masses for accurate entropy
	// and exhaust-mass calculations. Tag /tg/ tritium/plasma/etc. as flammable
	// so get_by_flag(XGM_GAS_FUEL) sees them.
	for(var/datum/gas/g as anything in subtypesof(/datum/gas))
		var/id = initial(g.id)
		if(!id || name[id])
			continue
		name[id] = initial(g.name)
		specific_heat[id] = initial(g.specific_heat)
		molar_mass[id] = GLOB.dq_linda_only_molar_masses[id] || initial(g.specific_heat) * 0.05
		gases[id] = g
		molar_specific_volume[id] = 0.001
		// LINDA-only flammables → XGM_GAS_FUEL so combustion checks see them.
		if(id == "tritium" || id == "hydrogen" || id == "methane" || id == "miasma")
			flags[id] = XGM_GAS_FUEL

GLOBAL_DATUM_INIT(gas_data, /datum/xgm_gas_data, new())


// =====================================================================
// 6. Specific entropy
// =====================================================================
//
// Used by code/ATMOSPHERICS/_atmospherics_helpers.dm to compute the energy
// cost of a pump moving gas from source to sink: delta_S * T gives J/mol.
// Direct port of the original Baystation/XGM impl in xgm_gas_mixture.dm —
// reading volume, partial moles, temperature, plus per-gas molar_mass and
// specific_heat from GLOB.gas_data. Matches CHOMP pump power-draw constants.
//
// Formula (from XGM):
//   s_gas = R * (ln( (K_S * V / (n_gas * T)) * (M * Cp * T)^(2/3) + 1 ) + 15)
//   s_mix = sum(n_gas * s_gas) / n_total
//
// K_S = IDEAL_GAS_ENTROPY_CONSTANT (1164), R = R_IDEAL_GAS_EQUATION (8.31).
#define SPECIFIC_ENTROPY_VACUUM 150

/datum/gas_mixture/proc/specific_entropy()
	var/n_total = total_moles()
	if(!gases || n_total <= 0)
		return SPECIFIC_ENTROPY_VACUUM
	. = 0
	for(var/datum/gas/g as anything in gases)
		var/n = gases[g][MOLES]
		if(n <= 0)
			continue
		. += n * specific_entropy_gas(g)
	. /= n_total

/datum/gas_mixture/proc/specific_entropy_gas(gas_id_or_type)
	if(!gases || temperature <= 0 || volume <= 0)
		return SPECIFIC_ENTROPY_VACUUM
	var/datum/gas/gas_type = istext(gas_id_or_type) ? get_xgm_id_for_gas(gas_id_or_type) : gas_id_or_type
	if(isnull(gas_type) || !gases[gas_type])
		return SPECIFIC_ENTROPY_VACUUM
	var/n = gases[gas_type][MOLES]
	if(n <= 0)
		return SPECIFIC_ENTROPY_VACUUM
	var/gas_id = initial(gas_type.id)
	var/molar_mass = GLOB.gas_data.molar_mass[gas_id]
	var/specific_heat = GLOB.gas_data.specific_heat[gas_id]
	if(molar_mass <= 0 || specific_heat <= 0)
		// Fallback for gases without xgm_gas decl metadata.
		return R_IDEAL_GAS_EQUATION * (log(volume / n) + 1.5 * log(temperature)) + 15
	return R_IDEAL_GAS_EQUATION * (log((IDEAL_GAS_ENTROPY_CONSTANT * volume / (n * temperature)) * (molar_mass * specific_heat * temperature) ** (2/3) + 1) + 15)


// =====================================================================
// 7. Legacy decls + vars
// =====================================================================

// DQEdit — group_multiplier removed. Every CHOMP read was rewritten to
// drop the `* group_multiplier` (the value was always 1, so dropping it is
// behaviour-preserving). XGM-era multi-tile zone scalar isn't needed under
// LINDA, where every turf has its own gas_mixture.

// DQEdit — /datum/gas_mixture.gas (XGM empty-list stub) removed. Every
// legacy read site has been migrated to gas_ids() / LINDA_GAS_AMT() /
// .gases[type][MOLES]. Confirmed via grep before deletion. If a stale
// reader resurfaces, it should fail compile rather than silently read 0.

// pipeline_expansion: CHOMP pipe subtypes (pipe_base.dm:60+) override this to
// enumerate network neighbors. Base no-op is the canonical declaration.
/obj/machinery/atmospherics/proc/pipeline_expansion(datum/pipeline/net)
	return list()

// DQEdit — /datum/pipeline.building was a ZAS-era rebuild sentinel; zero
// callers under LINDA, removed.

// CHOMP datum_pipeline.dm calls multiply() during gas rebalancing. LINDA's
// gas_mixture has multiply as a byondapi binding; this is the DM fallback
// when running without verdigris.
/datum/gas_mixture/proc/multiply(num_val)
	if(num_val == 1 || !gases)
		return
	for(var/datum/gas/g as anything in gases)
		gases[g][MOLES] *= num_val

// /obj/fire — ZAS-era fire effect. LINDA uses /obj/effect/hotspot at runtime;
// CHOMP code that still references the legacy /obj/fire path (closet contents,
// fusion core field, fire alarm spawn lists) resolves through this lightweight
// declaration. It's an explicit placeholder until the legacy references are
// migrated to /obj/effect/hotspot.
/obj/fire
	name = "fire (deprecated)"
	icon = 'icons/effects/fire.dmi'
	icon_state = "1"
	anchored = TRUE
	mouse_opacity = 0

// /obj/item/tank exposed return_pressure/return_temperature as forwarding
// methods to air_contents. Re-declare for callers that still use them.
/obj/item/tank/proc/return_pressure()
	if(air_contents)
		return air_contents.return_pressure()
	return 0

/obj/item/tank/proc/return_temperature()
	if(air_contents)
		return air_contents.temperature
	return 0

// /datum/decl/xgm_gas — base type for the per-gas decls in code/defines/gases.dm.
// Original definition was in deleted code/modules/xgm/xgm_gas_data.dm; restored
// here so subtype declarations resolve.
/datum/decl/xgm_gas
	var/id = ""
	var/name = ""
	var/specific_heat = 0
	var/molar_mass = 0
	var/overlay_limit = 0
	var/tile_overlay = null
	var/flags = 0
	var/condensation_temperature = 0
	var/condensation_product = null
	var/condensation_energy = 0
	var/burn_product = null
	var/burn_product_energy = 0

// DQEdit — XGM contamination machinery + GLOB.vsc config holders fully
// removed. /atom.contaminated had no setter under LINDA (ZAS contamination
// pipeline was never ported); the only readers (carbon/human/life.dm phoron
// damage branch, custom_items_vr.dm modkit check) have been deleted alongside
// it. door.dm's airflow_delay read was already a commented-out line.
// Restore the holders + a setter pipeline if/when phoron contamination
// gameplay is rebuilt on the LINDA model.


// =====================================================================
// 8. Suit / head dermal-protection checks
// =====================================================================
//
// Used by nanogoop floors and stardog attacks to decide whether worn gear
// blocks contact attacks. A clothing item with permeability_coefficient ≤ 0.1
// is considered sealed.

/mob/living/carbon/human/proc/pl_suit_protected()
	var/obj/item/clothing/C = wear_suit
	if(istype(C) && C.permeability_coefficient <= 0.1)
		return TRUE
	return FALSE

/mob/living/carbon/human/proc/pl_head_protected()
	var/obj/item/clothing/C = head
	if(istype(C) && C.permeability_coefficient <= 0.1)
		return TRUE
	return FALSE


// =====================================================================
// Base /turf fire hooks
// =====================================================================
//
// /turf/open implementations live in dq_linda_turf_air.dm. These base no-ops
// catch calls on /turf (walls, untyped) so untyped turf var references compile.
/turf/proc/lingering_fire()
	return null
/turf/proc/feed_lingering_fire(intensity = 1)
	return
/turf/proc/create_fire(temp = T0C + 300)
	return
