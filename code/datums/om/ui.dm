// Object-model core: UI binding (doc/rewrite/object_model_core.md section J),
// Rust-owned watches (A.6) and dt helpers (K).

/// Minimum deciseconds between two pushes to one session.
#define OM_UI_THROTTLE (2)

/// Binds a UI session to `target`: a watch edge on `mask` that raises the
/// target to RELEVANCE_WATCHED while bound. Changes are coalesced and pushed
/// at most once per OM_UI_THROTTLE per session via session.om_ui_push().
/proc/om_ui_bind(datum/session, datum/target, mask)
	var/datum/om/behaviour/B = om_registry().ui_behaviour
	om_attach(session, B)
	om_watch(session, target, mask, B)
	om_observe(target, session, RELEVANCE_WATCHED)

/proc/om_ui_unbind(datum/session, datum/target)
	var/datum/om/behaviour/B = om_registry().ui_behaviour
	om_unwatch(session, target, B)
	om_unobserve(target, session)
	if(!length(session.om_rec?.watching))
		om_detach(session, B)

/// Binds every ui row of `E`'s decls (target proc, watch mask) for `session`.
/proc/om_ui_bind_table(datum/session, datum/E)
	var/datum/om/rec/rec = om_rec_of(E)
	if(!rec)
		return
	for(var/list/row as anything in rec.table.ui)
		var/datum/target = row["target"] ? call(E, row["target"])() : E
		if(target)
			om_ui_bind(session, target, row["watch"] || CHANGE_GENERIC_MASK)

/// The rates a ui row streams, as name -> list(value, rate, at).
/proc/om_ui_stream(datum/E)
	. = list()
	var/datum/om/rec/rec = E?.om_rec
	if(!rec)
		return
	for(var/list/row as anything in rec.table.ui)
		for(var/name in row["stream_rates"])
			var/datum/om/rate/R = om_rate_named(E, name)
			if(R)
				.[name] = om_ui_rate(R)

/// Rate streaming: the client interpolates value + rate * (now - at).
/proc/om_ui_rate(datum/om/rate/R)
	return list("value" = R.now(), "rate" = R.per_second, "at" = R.sched_now())

/// Called on the session when a bound target changed. /datum/tgui pushes an update.
/datum/proc/om_ui_push()
	return

/datum/tgui/om_ui_push()
	send_update()

/datum/om/behaviour/internal/ui_push
	name = "om: ui push"
	lane = LANE_PRESENTATION

/datum/om/behaviour/internal/ui_push/on_wake(datum/session, changes)
	var/datum/om/rec/rec = session.om_rec
	var/t = rec.sched.now()
	var/wait = rec.ui_last_push + OM_UI_THROTTLE - t
	if(rec.ui_last_push && wait > 0)
		if(!om_deadline_pending(session, src))
			om_after(session, wait, src)
		return
	rec.ui_last_push = t
	session.om_ui_push()

/datum/om/behaviour/internal/ui_push/on_deadline(datum/session)
	var/datum/om/rec/rec = session.om_rec
	rec.ui_last_push = rec.sched.now()
	session.om_ui_push()

#undef OM_UI_THROTTLE

// ---------------------------------------------------------------- native (Rust) watches

// The DM half of Rust-owned watches. A behaviour declares wake_on_native
// bits; when it attaches, om_native_watch() tells the bridge which bits this
// entity needs. The reactor's drain calls om_native_deliver(E, bits) once per
// tick per entity, which runs on_native(E, bits) on each started behaviour
// declaring any of those bits. The bridge procs below are the stub interface:
// the reactor track replaces their bodies with its generated bindings.

/// Stub: register interest in native `bits` for `E` (reactor binding goes here).
/proc/om_native_bridge_watch(datum/E, bits)
	return FALSE

/// Stub: tell the native side `E`'s relevance level (reactor binding goes here).
/proc/om_native_bridge_relevance(datum/E, level)
	return FALSE

/proc/om_native_watch(datum/om/rec/rec)
	var/bits = 0
	for(var/datum/om/behaviour/B as anything in rec.att)
		bits |= B.wake_on_native
	if(bits != rec.native_bits)
		rec.native_bits = bits
		om_native_bridge_watch(rec.owner, bits)

/// Called by the reactor drain.
/proc/om_native_deliver(datum/E, bits)
	var/datum/om/rec/rec = E?.om_rec
	if(!rec || rec.torn_down)
		return
	for(var/i in 1 to length(rec.att))
		var/datum/om/behaviour/B = rec.att[i]
		if((B.wake_on_native & bits) && (rec.att_state[i] & OM_ATT_STARTED))
			rec.sched.call_hook(rec, B, OM_HOOK_NATIVE, B.wake_on_native & bits)

/proc/om_native_relevance(datum/E, level)
	if(E)
		om_native_bridge_relevance(E, level)

// ---------------------------------------------------------------- dt helpers

/// Exponential approach of `x` toward `target` with rate `k` per second over `dt` seconds.
/// Exact for any dt: two half-steps equal one full step.
/proc/approach(x, target, k, dt)
	return target + (x - target) * NUM_E ** (-k * dt)

/// Exponential decay of `x` at `rate` per second over `dt` seconds.
/proc/decay(x, rate, dt)
	return x * NUM_E ** (-rate * dt)

/// TRUE with the probability that an event of `p_per_second` (0-1) happens within `dt` seconds.
/proc/chance_over(p_per_second, dt)
	if(p_per_second <= 0 || dt <= 0)
		return FALSE
	if(p_per_second >= 1)
		return TRUE
	return rand() < 1 - (1 - p_per_second) ** dt

/// Linear move of `x` toward `target` by at most `speed * dt`.
/proc/move_toward(x, target, speed, dt)
	var/delta = speed * dt
	if(abs(target - x) <= delta)
		return target
	return x + (target > x ? delta : -delta)

/proc/clamp01(x)
	return clamp(x, 0, 1)
