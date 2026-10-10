// A gas level (doc/rewrite/final_api.html section 14 note "Gas watches"; doc/rewrite/framework_gaps.md F5): a tracked var of the holder that says
// whether the gas it stands in, or holds, is past a level. The holder reacts to the var with on_change(); nothing polls and nothing reads the gas.
//
//   gas_level(into = nameof(overheated), reading = CH_GAS_TEMPERATURE, above = ARTIFACT_HEAT_BREAK, hysteresis = 50)
//   on_change(nameof(overheated), ENTER, then(PROC_REF(burst)))
//   TRACKED(/obj/machinery/artifact, overheated)                                     // the holder declares the var and its setter
//
// `into` names the holder's tracked var (a boolean, FALSE until the level is passed). `reading` is a CH_GAS_* channel (pressure kPa, temperature K,
// total moles, oxygen, plasma or carbon dioxide moles). Give `above` (the var is TRUE at that value or over) or `below` (at it or under).
// `hysteresis` is the distance back past the level the reading must travel before the var turns FALSE again (-1: the channel's own), so a reading
// resting on the level does not chatter. `air` names the holder var holding the mixture; null is the air of the turf the holder stands on, and the
// holder calls gas_level_rearm_all() when it moves. A holder with several levels gives each its own `into`.
//
// The edge is found in Rust. The level is a threshold watch on the mixture's cell (world_watch_when(), verdigris/ffi/src/sched.rs): Rust compares the
// reading with the level on every change it sees, wherever the write came from (a heat exchanger or a pipe device writing a region reaches it the
// same as a gas write: the mirror of a watched pipe region is refreshed from the network's own revision), and DM hears only the crossing, on the
// lane (urgent by default). A burst of crossings in one tick reaches DM as one wake (Rust merges them per watch), the tracked setter ignores a
// value it already holds, and on_change() runs its parts once per drain however many times the var moved (at_most = t on the on_change spaces the
// runs further). A reading that never reaches the level costs DM nothing.
//
// The var follows the mixture: atmos_air_set() re-arms the level when the var holding it is pointed at another mixture, and the var is set from
// the new mixture's reading at once. A holder with no mixture reads FALSE. The var is also settled at arming, so a holder that starts past its
// level is told the first drain. Reading the gas stream itself (every change in a part of the gas) is gas_watch().

CAPABILITY_TYPE(gas_level, CAP_GAS_LEVEL, /datum/capability/lib/gas_level, key = into, into = null, reading = CH_GAS_PRESSURE, above = null, below = null, hysteresis = -1, air = null, lane = LANE_URGENT)

/datum/capability/lib/gas_level
	holder_hooks = HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/lib/gas_level/cap_data_type()
	return /datum/cap_data/gas_level

/// The holder's level watch and the mixture it is on.
/datum/cap_data/gas_level
	/// The world threshold watch on the mixture, or null while the holder has none.
	var/tmp/datum/native_watch/world/watch
	/// Arena id of the mixture `watch` is on.
	var/armed_id
	/// The holder whose var the crossing turns (a plain reference, cleared when it dies) and that var's name.
	var/atom/holder
	var/into_var

CAPABILITIES(/datum/cap_data/gas_level)
	owns_one(nameof(watch), /datum/native_watch/world)
	ref_one(nameof(holder), /atom)

/datum/capability/lib/gas_level/on_holder_init(datum/act/eval/A)
	gas_level_arm(A.holder, src)

/datum/capability/lib/gas_level/on_holder_destroy(datum/act/eval/A)
	var/datum/cap_data/gas_level/data = gas_level_data(A.holder, src)
	if(!data)
		return
	own_clear(data, nameof(data.watch), OWN_DELETE)
	data.armed_id = null
	rel_clear(data, nameof(data.holder))

/// The level record of `holder`'s level `def`, or null.
/proc/gas_level_data(datum/holder, datum/capability/lib/gas_level/def)
	RETURN_TYPE(/datum/cap_data/gas_level)
	var/datum/activation/act = cap_activation(holder, CAP_GAS_LEVEL, def.into, TRUE)
	return act ? activation_data(act) : null

/// The hysteresis the Rust channel `channel` declares (verdigris/domains/gas/src/cell.rs), in the channel's unit.
/proc/gas_level_channel_hysteresis(channel)
	switch(channel)
		if(CH_GAS_MOLES)
			return 0.1
		if(CH_GAS_OXYGEN, CH_GAS_PLASMA, CH_GAS_CARBON_DIOXIDE)
			return 0.05
	return 0.5

/// The reading of `mixture` on `channel`.
/proc/gas_level_read(datum/gas_mixture/mixture, channel)
	switch(channel)
		if(CH_GAS_PRESSURE)
			return mixture.return_pressure()
		if(CH_GAS_TEMPERATURE)
			return mixture.return_temperature()
		if(CH_GAS_MOLES)
			return mixture.total_moles()
		if(CH_GAS_OXYGEN)
			return mixture.get_moles(/datum/gas/oxygen)
		if(CH_GAS_PLASMA)
			return mixture.get_moles(/datum/gas/plasma)
		if(CH_GAS_CARBON_DIOXIDE)
			return mixture.get_moles(/datum/gas/carbon_dioxide)
	CRASH("gas_level: unknown channel [channel]")

/datum/capability/lib/gas_level/proc/limit_value()
	return isnull(above) ? below : above

/datum/capability/lib/gas_level/proc/hysteresis_value()
	return hysteresis < 0 ? gas_level_channel_hysteresis(reading) : hysteresis

/// Sets the holder's var from `mixture`'s reading now: past the level it turns TRUE, back past the level by the hysteresis it turns FALSE, and in
/// between it keeps its value (the same rule Rust applies to its crossings).
/datum/capability/lib/gas_level/proc/settle(datum/holder, datum/gas_mixture/mixture)
	var/side = !!holder.vars[into]
	var/new_side = side
	if(mixture)
		var/value = gas_level_read(mixture, reading)
		var/limit = limit_value()
		var/margin = hysteresis_value()
		if(isnull(above))
			if(value <= limit)
				new_side = TRUE
			else if(value >= limit + margin)
				new_side = FALSE
		else
			if(value >= limit)
				new_side = TRUE
			else if(value <= limit - margin)
				new_side = FALSE
	else
		new_side = FALSE
	if(new_side != side)
		call(holder, "set_[into]")(new_side)

/// Points `holder`'s level `def` at its mixture now: nothing is re-armed when it is the one already watched, and the var is settled either way.
/proc/gas_level_arm(atom/holder, datum/capability/lib/gas_level/def)
	var/datum/cap_data/gas_level/data = gas_level_data(holder, def)
	if(!data)
		return
	if(isnull(def.into) || !hascall(holder, "set_[def.into]") || (isnull(def.above) == isnull(def.below)))
		declare_report("gas_level on [holder.type]: it needs a tracked var `into` with a setter, and exactly one of above and below")
		return
	rel_set(data, nameof(data.holder), holder)
	data.into_var = def.into
	var/datum/gas_mixture/mixture = gas_air_of(holder, def.air)
	var/id = mixture?.arena_id()
	if(id == data.armed_id && (data.watch || isnull(id)))
		def.settle(holder, mixture)
		return
	own_clear(data, nameof(data.watch), OWN_DELETE)
	data.armed_id = id
	if(!isnull(id))
		var/condition = list(WORLD_COND_THRESHOLD, WORLD_GAS_HANDLE(mixture), def.reading, isnull(def.above) ? WORLD_CMP_BELOW : WORLD_CMP_ABOVE, def.limit_value(), def.hysteresis_value(), TRUE)
		rel_set(data, nameof(data.watch), world_watch_when(data, condition, TYPE_PROC_REF(/datum/cap_data/gas_level, crossed), def.lane))
	def.settle(holder, mixture)

/// Re-arms every level of `holder` (it moved, or its air was pointed at another mixture).
/proc/gas_level_rearm_all(atom/holder)
	var/datum/type_table/T = table_of(holder)
	for(var/datum/capability/lib/gas_level/def as anything in table_cap_defs(T, CAP_GAS_LEVEL))
		gas_level_arm(holder, def)

/// Rust reported the reading crossing the level: the holder's var follows.
/datum/cap_data/gas_level/proc/crossed(datum/native_watch/world/W, reason, source, source_kind)
	var/atom/target = holder
	if(!target || QDELETED(target))
		return
	var/datum/capability/lib/gas_level/def = cap_of(target, CAP_GAS_LEVEL, into_var)
	if(!def)
		return
	var/datum/gas_mixture/mixture = gas_air_of(target, def.air)
	if(!mixture || mixture.arena_id() != armed_id)
		return // the holder's air was pointed elsewhere since: its re-arm settles the var
	def.settle(target, mixture)
