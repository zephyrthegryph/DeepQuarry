// ---------------------------------------------------------------- native (Rust) watches

// The DM half of Rust-owned watches. A behaviour declares wake_on_native
// bits; when it attaches, entity_native_watch() tells the bridge which bits this
// entity needs. The reactor's drain calls entity_native_deliver(E, bits) once per
// tick per entity, which runs on_native(E, bits) on each started behaviour
// declaring any of those bits. The bridge procs below are the stub interface:
// the reactor track replaces their bodies with its generated bindings.

/// Stub: register interest in native `bits` for `E` (reactor binding goes here).
/proc/entity_native_bridge_watch(datum/E, bits)
	return FALSE

/// Stub: tell the native side `E`'s relevance level (reactor binding goes here).
/proc/entity_native_bridge_relevance(datum/E, level)
	return FALSE

/proc/entity_native_watch(datum/scheduler_record/rec)
	var/bits = 0
	for(var/datum/scheduled_behaviour/B as anything in rec.att)
		bits |= B.wake_on_native
	if(bits != rec.native_bits)
		rec.native_bits = bits
		entity_native_bridge_watch(rec.owner, bits)

/// Called by the reactor drain.
/proc/entity_native_deliver(datum/E, bits)
	var/datum/scheduler_record/rec = E?.om_rec
	if(!rec || rec.torn_down)
		return
	for(var/i in 1 to length(rec.att))
		var/datum/scheduled_behaviour/B = rec.att[i]
		if((B.wake_on_native & bits) && (rec.att_state[i] & OM_ATT_STARTED))
			rec.sched.call_hook(rec, B, OM_HOOK_NATIVE, B.wake_on_native & bits)

/proc/entity_native_relevance(datum/E, level)
	if(E)
		entity_native_bridge_relevance(E, level)
