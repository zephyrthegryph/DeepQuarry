// Generic threshold-watch helper for OM-pipeline machines (doc/rewrite/object_model_core.md,
// code/game/machinery/machine_pipeline.dm).
//
// Scope note: the ask this grew from wanted one `om_watch(E, source, field, bands, channel)`
// that arms a threshold set on *any* Rust `#[vg::component]` field. That primitive does not
// exist in verdigris today — only two shapes of Rust-side threshold watch exist
// (`vg_heat_watch*`/`vg_react_watch_*`, both domain-specific) plus the gas-mixture *dirty*
// watch (`vg_watch_dirty_gas_mixture`/`vg_drain_dirty_gas_observations`, already wired end to
// end through SSmachines' subscribe_gas_dependency()/gas_dependency_changed() transport and its
// flat GAS_DEPENDENCY_OBSERVATION_STRIDE observation array). Adding a generic per-field
// component watch is new Rust work on the gas/component domains that rewrite/rust-core2 owns —
// out of scope for this DM-only worktree, and deliberately not attempted or faked here.
//
// What this file actually gives OM machines, on top of what already exists:
//  - om_watch_gas(mixture, bands, channel): arms/re-arms a set of threshold bands (pressure,
//    temperature, or a named gas's moles) on a gas mixture, using the existing dirty-gas-mixture
//    transport as the delivery mechanism. A crossing raises om_changed(E, channel).
//  - om_watch_derived(bands, channel, getter): a DM-side value (no Rust watch backs it) that is
//    re-evaluated whenever the caller re-checks it (om_watch_recheck), so callers that combine a
//    derived condition with a gas band go through the same band/crossing/hysteresis code.
//  - Re-arming a channel replaces its previous watch; om_unwatch_all() (called from Destroy())
//    releases every watch a machine holds.

/// One band: a field name, a comparison edge, the threshold value and a hysteresis margin (in
/// the field's own units) so a value sitting exactly on the edge doesn't chatter.
/datum/om_watch_band
	var/field
	var/above // TRUE: armed when field >= value; FALSE: armed when field <= value
	var/value
	var/hysteresis = 0

/datum/om_watch_band/New(field, above, value, hysteresis = 0)
	src.field = field
	src.above = above
	src.value = value
	src.hysteresis = hysteresis

/// Per-entity, per-channel watch state.
/datum/om_watch
	var/datum/weakref/entity_ref
	var/channel
	var/list/datum/om_watch_band/bands
	var/list/last_side // "field:above:value" -> TRUE/FALSE at last evaluation
	var/mixture_id // set only for a gas-mixture watch
	var/derived // TRUE for a DM-side value with no Rust watch backing it
	var/derived_value // the last value a derived getter reported, for om_watch_recheck()

/datum/om_watch/proc/gas_field_value(list/observation, observation_index, field)
	switch(field)
		if("pressure")
			return observation[observation_index + 3]
		if("temperature")
			return observation[observation_index + 4]
		if("volume")
			return observation[observation_index + 5]
		if("o2")
			return observation[observation_index + 6]
		if("co2")
			return observation[observation_index + 7]
		if("plasma")
			return observation[observation_index + 8]
		if("methane")
			return observation[observation_index + 9]
		if("n2o")
			return observation[observation_index + 10]
		if("volatile_fuel")
			return observation[observation_index + 11]
		if("miasma")
			return observation[observation_index + 12]
		if("zauker")
			return observation[observation_index + 13]
		if("total_moles")
			return observation[observation_index + 14]
	return null

/// Evaluates every band against `current_value` (already read, from either the gas observation
/// stride or a derived getter). Returns TRUE the first time any band crosses its edge;
/// hysteresis holds off re-firing until the value clears back past the margin.
/datum/om_watch/proc/evaluate_band(datum/om_watch_band/B, current_value)
	if(isnull(current_value))
		return FALSE
	if(!last_side)
		last_side = list()
	var/key = "[B.field]:[B.above]:[B.value]"
	var/edge = B.above ? (current_value >= B.value) : (current_value <= B.value)
	var/prior = last_side[key]
	if(isnull(prior))
		last_side[key] = edge
		return FALSE
	if(edge == prior)
		return FALSE
	if(!edge && B.hysteresis > 0)
		var/settled = B.above ? (current_value <= B.value - B.hysteresis) : (current_value >= B.value + B.hysteresis)
		if(!settled)
			return FALSE
	last_side[key] = edge
	return TRUE

/// Re-evaluates every band of a gas watch against one delivered observation. Returns TRUE the
/// first time any band crosses.
/datum/om_watch/proc/evaluate_gas(list/observation, observation_index)
	. = FALSE
	for(var/datum/om_watch_band/B as anything in bands)
		if(evaluate_band(B, gas_field_value(observation, observation_index, B.field)))
			. = TRUE

/// Re-evaluates every band of a derived watch against the latest getter result. Returns TRUE the
/// first time any band crosses.
/datum/om_watch/proc/evaluate_derived(current_value)
	derived_value = current_value
	. = FALSE
	for(var/datum/om_watch_band/B as anything in bands)
		if(evaluate_band(B, current_value))
			. = TRUE

/// Arms (or re-arms) a gas-mixture band watch on `channel`, replacing whatever was previously
/// watching that channel. A crossing calls om_changed(src, channel) from
/// /obj/machinery/gas_dependency_changed() (machinery.dm) the next time SSmachines delivers a
/// dirty-mixture notification for this mixture.
/obj/machinery/proc/om_watch_gas(datum/gas_mixture/mixture, list/datum/om_watch_band/bands, channel)
	om_unwatch(channel)
	var/new_mixture_id = mixture?.arena_id()
	if(isnull(new_mixture_id))
		return
	var/datum/om_watch/W = new
	W.entity_ref = WEAKREF(src)
	W.channel = channel
	W.bands = bands
	W.mixture_id = new_mixture_id
	LAZYSET(om_watches, channel, W)
	SSmachines.sleeping_gas_devices[W.entity_ref.reference] = W.entity_ref
	SSmachines.subscribe_gas_dependency(new_mixture_id, W.entity_ref)

/// Registers a DM-side derived watch: no Rust watch backs it, so the caller is responsible for
/// calling om_watch_recheck(channel, getter()) whenever something that could move the value
/// happens (a producer's job, same as any other CHANGE_MACHINE_* channel).
/obj/machinery/proc/om_watch_derived(list/datum/om_watch_band/bands, channel, current_value)
	var/datum/om_watch/W = new
	W.entity_ref = WEAKREF(src)
	W.channel = channel
	W.bands = bands
	W.derived = TRUE
	LAZYSET(om_watches, channel, W)
	W.evaluate_derived(current_value) // seed last_side without firing on registration

/obj/machinery/proc/om_watch_recheck(channel, current_value)
	var/datum/om_watch/W = om_watches?[channel]
	if(!W || !W.derived)
		return
	if(W.evaluate_derived(current_value))
		om_changed(src, channel)

/obj/machinery/proc/om_unwatch(channel)
	var/datum/om_watch/W = om_watches?[channel]
	if(!W)
		return
	var/datum/weakref/WR = W.entity_ref
	if(!isnull(W.mixture_id) && WR)
		SSmachines.unsubscribe_gas_dependency(W.mixture_id, WR)
	LAZYREMOVE(om_watches, channel)
	if(!LAZYLEN(om_watches) && WR?.reference)
		SSmachines.sleeping_gas_devices.Remove(WR.reference)

/obj/machinery/proc/om_unwatch_all()
	if(!om_watches)
		return
	for(var/channel in om_watches.Copy())
		om_unwatch(channel)
