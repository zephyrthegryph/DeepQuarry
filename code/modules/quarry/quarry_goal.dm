// Quarry goals.
//
// A goal is one trackable objective on a layer. The layer's goals are
// supplied by its floor archetype's build_goals() and ARE the floor's
// clear condition: a layer unlocks the next-deeper depth once every one
// of its goals is satisfied (see /datum/quarry_floor_archetype/is_cleared).
//
// Each /datum/quarry_goal instance is owned by a /datum/quarry_layer and
// tracks its own progress; a goal is satisfied at 100% of its target.
//
// Goal kinds (this file plus quarry_archetype_goals.dm): mine_node,
// kill_mob, map_tiles, pump_reagent, vent_gas, survive_timer, neutralize,
// deliver_resource, power_output.

/datum/quarry_goal
	// Human-readable name shown in the elevator UI.
	var/name = "Stabilization Goal"
	// Long-form description; second line on the UI card.
	var/description = ""
	// Numeric target. Units depend on the subtype.
	var/target = 1
	// Current progress toward target. Clamped 0..target.
	var/progress = 0
	// Layer this goal belongs to. Set when the layer rolls the goal.
	var/datum/quarry_layer/owner_layer = null

// Percent complete, clamped 0..100.
/datum/quarry_goal/proc/percent_complete()
	if(target <= 0)
		return 100
	return min(100, round(100 * progress / target))

// TRUE once the goal counts as satisfied (fully complete). Gates the
// floor's clear condition (archetype.is_cleared) and the UI checkmark.
/datum/quarry_goal/proc/is_satisfied()
	return progress >= target

// Resource-identity string used to fold duplicate goals from multiple
// features into a single combined goal at layer build time. Two
// /datum/quarry_goal instances of the same subtype with the same
// merge_key are merged: targets are summed, progress carries over
// from the first instance, name/description from the first instance.
//
// Default: a unique per-instance key (refbased) so unrelated goals
// don't accidentally fold. Subtypes that represent a specific
// resource override to return a stable string (mineral name, reagent
// id, gas id, mob type).
/datum/quarry_goal/proc/merge_key()
	return "[REF(src)]"

// Per-subtype hook for additional fields the snapshot should round-
// trip beyond name/description/target/progress. Returns an assoc list
// merged into the goal's JSON entry, or null for none.
/datum/quarry_goal/proc/serialize_extra()
	return null

// Counterpart to serialize_extra: read those fields back during
// restore. Default no-op; subtypes override.
/datum/quarry_goal/proc/deserialize_extra(list/data)
	return

// Concrete subtype hook: a mineral wall on this layer was just mined.
// Called with the wall's mineral name (string, e.g. ORE_PHORON) and
// the item typepath that DropMineral produced. Default no-op; mining
// goals override. Fires once per turf since GetDrilled changes the
// turf to a floor afterward.
/datum/quarry_goal/proc/on_node_mined(mineral_name, item_type)
	return

// Concrete subtype hook: a pool turf on this layer was just pumped
// for `units` of reagent `reagent_id`. Called once per pump tick per
// affected reagent. Default no-op; pump goals override.
/datum/quarry_goal/proc/on_reagent_pumped(reagent_id, units)
	return

// Concrete subtype hook: a gas vent on this layer just released
// `moles` of `gas_id` into a turf. Default no-op; gas goals override.
/datum/quarry_goal/proc/on_gas_vented(gas_id, moles)
	return

// Concrete subtype hook: given a mob that just died on this layer,
// add to progress as appropriate. Default no-op; only kill goals
// override.
/datum/quarry_goal/proc/on_mob_killed(mob/M)
	return

// Concrete subtype hook: a player walked on a new turf on this layer.
// Default no-op; only exploration goals override.
/datum/quarry_goal/proc/on_tile_visited(turf/T)
	return

// Concrete subtype hook: fired once per SSquarry tick for every goal on
// a loaded layer that has at least one live player. `seconds` is the
// subsystem wait in seconds, so sustained goals (survive timers, power
// output, ambient remediation) can accrue scaled progress. Default
// no-op; only time-based goals override. See SSquarry.tick_layer_goals.
/datum/quarry_goal/proc/on_layer_tick(datum/quarry_layer/L, seconds)
	return

// Concrete subtype hook: an archetype "objective" was resolved on this
// layer (a gas fissure sealed, a hive core destroyed, an outpost lit,
// a cure node cleansed, ...). `tag` identifies which objective kind.
// Default no-op; the generic neutralize goal overrides. See
// SSquarry.on_layer_objective and /obj/structure/quarry_objective.
/datum/quarry_goal/proc/on_objective_resolved(tag)
	return

// Concrete subtype hook: the freight elevator arrived at the surface
// carrying `count` deliverable items out of this layer. Default no-op;
// only the resource-delivery goal overrides. See SSquarry.on_layer_delivery.
/datum/quarry_goal/proc/on_delivery(count)
	return


// --- mine_node --------------------------------------------------------
//
// Extraction goal: mine N walls of a specific mineral. Counts on the
// drill event itself (GetDrilled), so the goal advances when the work
// happens — not when the haul reaches the surface. Match by either
// the mineral string name (ORE_PHORON) or the dropped item type.
/datum/quarry_goal/mine_node
	name = "Mining Quota"
	// String mineral name to match (e.g. ORE_PHORON). If set, takes
	// precedence over item_type.
	var/mineral_name = null
	// Fallback: item type DropMineral produced. Used when mineral_name
	// isn't set, or as a secondary check.
	var/item_type = null

/datum/quarry_goal/mine_node/on_node_mined(mn_name, it_type)
	if(mineral_name)
		if(mn_name != mineral_name)
			return
	else if(item_type)
		if(!ispath(it_type, item_type))
			return
	else
		return
	progress = min(target, progress + 1)

/datum/quarry_goal/mine_node/merge_key()
	return mineral_name ? "mineral:[mineral_name]" : "item:[item_type]"


// --- kill_mob ---------------------------------------------------------
//
// Combat goal: kill N mobs of a specific type on this layer.
/datum/quarry_goal/kill_mob
	name = "Pest Control"
	// Mob subtype to count.
	var/mob_type = /mob/living/simple_mob

/datum/quarry_goal/kill_mob/on_mob_killed(mob/M)
	if(!istype(M, mob_type))
		return
	progress = min(target, progress + 1)

/datum/quarry_goal/kill_mob/merge_key()
	return "mob:[mob_type]"


// --- map_tiles --------------------------------------------------------
//
// Exploration goal: visit N unique floor tiles on this layer.
/datum/quarry_goal/map_tiles
	name = "Survey the Shaft"
	// Tracking set of (x|y) keys already counted, so the same tile
	// doesn't tick the goal twice when the player walks back across it.
	var/list/seen_tiles = null

/datum/quarry_goal/map_tiles/on_tile_visited(turf/T)
	if(!T)
		return
	if(!seen_tiles)
		seen_tiles = list()
	var/key = "[T.x]|[T.y]"
	if(seen_tiles[key])
		return
	seen_tiles[key] = TRUE
	progress = min(target, progress + 1)

// Only one exploration goal per layer regardless of how many
// unmapped_passages features roll in — they all measure the same
// thing.
/datum/quarry_goal/map_tiles/merge_key()
	return "explore"

// Persist the visited-tile set so a player who comes back to the
// layer can't re-walk the same tiles to refill progress.
/datum/quarry_goal/map_tiles/serialize_extra()
	if(!seen_tiles || !length(seen_tiles))
		return null
	// Serialize keys only — the values are all TRUE. Keys are
	// short "X|Y" strings; ~256² tiles worst-case → small JSON.
	var/list/keys = list()
	for(var/k in seen_tiles)
		keys += k
	return list("seen_tiles" = keys)

/datum/quarry_goal/map_tiles/deserialize_extra(list/data)
	var/list/keys = data?["seen_tiles"]
	if(!islist(keys))
		return
	seen_tiles = list()
	for(var/k in keys)
		seen_tiles[k] = TRUE


// --- pump_reagent -----------------------------------------------------
//
// Pool-extraction goal: pump N units of a specific reagent ID out of
// the layer. Ticks on the pump's pump_reagents call against the pool
// turf, so the work (machinery + cell + time) is what counts. No bay
// dependency — the reagent doesn't even have to leave the layer.
/datum/quarry_goal/pump_reagent
	name = "Reagent Extraction"
	var/reagent_id = null

/datum/quarry_goal/pump_reagent/on_reagent_pumped(r_id, units)
	if(!reagent_id || r_id != reagent_id || !isnum(units) || units <= 0)
		return
	progress = min(target, progress + units)

/datum/quarry_goal/pump_reagent/merge_key()
	return "reagent:[reagent_id]"


// --- vent_gas ---------------------------------------------------------
//
// Gas-pocket goal: release N moles of a specific gas by mining the
// gas-bearing walls. Ticks when the raw_chem_vent item vents.
/datum/quarry_goal/vent_gas
	name = "Gas Extraction"
	var/gas_id = null

/datum/quarry_goal/vent_gas/on_gas_vented(g_id, moles)
	if(!gas_id || g_id != gas_id || !isnum(moles) || moles <= 0)
		return
	progress = min(target, progress + moles)

/datum/quarry_goal/vent_gas/merge_key()
	return "gas:[gas_id]"


// Goals are now produced by the feature pool — see quarry_feature.dm
// and quarry_features.dm. Each rolled /datum/quarry_feature contributes
// zero or more goals via its build_goals(layer) factory. They aggregate
// onto the layer's goals list inside generate_layer / restore_layer.
