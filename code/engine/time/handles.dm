// Handles and weak arguments (the time engine: doc/rewrite/framework_gaps.md C1).
//
// A handle names a datum without keeping it alive: handle_of(D) -> a number, handle_get(h) -> D or null (code/engine/refs/slots.dm: a slot table
// with a generation per slot, the same model as the Rust core's handles). A deleted datum's slot is freed and its generation bumped, so a stale
// handle never resolves to whatever reuses the slot. Every deferred record in the engine (timers and their keyed and real-time forms, I/O
// callbacks, timed actions) holds its datum arguments as handles, never as references: a record can outlive what it names without keeping it
// alive.
//
// A handle is one whole number, so it is a window payload value, a Topic href part or a key of an alist (never of a plain list: a number would index it).
// handle_get() also reads the text of one number (a href parameter).
//
// A turf has no slot to take: its handle is the text of its position, led by a scramble so the strings hash well, and, once its z-level has
// been released and reused, that level's generation. Resolving one reads a cached packed position (handle_turf_pos), parsing the key only the
// first time. A client's is "@ckey#connection".

/// A datum whose collection without qdel() is the signal it exists to give (a stack canary: BYOND frees it when the stack that held it ends). A
/// handle to one resolves null once it is gone and files no HANDLE TARGET COLLECTED report; every other type's handle does.
/datum/handle_sentinel

/// A turf's plain handle (its key, the z-level never released) -> its position packed as x + 512 * (y + 512 * z), read by handle_get().
/// A level too big to pack (x or y over 511, z over 63) is parsed each time instead.
GLOBAL_ALIST_EMPTY(handle_turf_pos)
/// A turf's packed position -> its key text, made once.
GLOBAL_ALIST_EMPTY(handle_turf_texts)

/// The last connection number a client handle took (handle_of() of a client).
GLOBAL_VAR_INIT(client_handle_gen, 0)

/// This connection's number in its handle, 0 until handle_of() is first called on it: a reconnect is a new /client with a new number.
/client/var/tmp/handle_gen = 0

/// A turf's key text: "<scramble>t<x>:<y>:<z>", the scramble first so BYOND's string table spreads the keys of neighbouring turfs.
/proc/handle_turf_key(turf/T)
	var/packed = T.x + 512 * (T.y + 512 * T.z)
	. = GLOB.handle_turf_texts[packed]
	if(.)
		return
	. = "[(T.x * 31 + T.y * 7 + T.z) % 997]t[T.x]:[T.y]:[T.z]"
	GLOB.handle_turf_texts[packed] = .

/// The turf a handle_turf_key() names, or null.
/proc/handle_turf_locate(key)
	var/turf_at = findtext(key, "t")
	if(!turf_at)
		return null
	var/x_end = findtext(key, ":", turf_at + 1)
	var/y_end = findtext(key, ":", x_end + 1)
	return locate(text2num(copytext(key, turf_at + 1, x_end)), text2num(copytext(key, x_end + 1, y_end)), text2num(copytext(key, y_end + 1)))

/// The handle of a turf or a client, which have no slot to take: text. A turf's is its key (handle_turf_key()), with "#<generation>" once its
/// z-level has been released and reused: turfs are never deleted and a turf's position survives ChangeTurf() (which resets the turf's vars).
/// A client's is "@ckey#connection", resolved through GLOB.directory and null for any other connection of that ckey.
/proc/handle_keyed_of(datum/D)
	READS_FROM() // a handle is the datum's stable id: the slot table it reads is identity bookkeeping, not state a draw or condition depends on
	if(isturf(D))
		var/turf/T = D
		var/key = "[handle_turf_key(T)]" // said as text, so the result is plainly text to the untyped lint
		var/gen = relation_z_generation(T.z)
		return gen ? "[key]#[gen]" : key
	if(isclient(D))
		var/client/C = D
		// A client is its ckey and its connection: "@ckey#n". It reads null while that player is disconnected and never names the client of a
		// later connection (relations proposal D10); a need that survives a reconnect keeps the ckey or the persistent_client.
		if(!C.handle_gen)
			C.handle_gen = ++GLOB.client_handle_gen
		return "@[C.ckey]#[C.handle_gen]"
	return null

/// The handle `D` already has, even while `D` is being deleted (until phase 5 releases it), or null
/// if it never had one. Never allocates. For taking a dying datum out of a handle-keyed list.
/proc/entity_handle_of(datum/D)
	READS_FROM() // the same identity bookkeeping as handle_of()
	if(isturf(D) || isclient(D))
		return handle_keyed_of(D)
	if(!isdatum(D))
		return null
	var/id = D.handle_slot
	if(!id || id > length(handle_gens))
		return null
	return id + SLOT_SPAN * handle_gens[id]

/// TRUE if handle `h` names `D`, even while `D` is being deleted (until phase 5
/// releases its slot). A handle accessor (`owner()` = handle_get(owner_handle))
/// reads null once its target is QDELETED, so `owner() == src` is FALSE inside
/// src's own teardown: compare with entity_handle_is(owner_handle, src) there.
/proc/entity_handle_is(h, datum/D)
	if(!h || !D)
		return FALSE
	return h == entity_handle_of(D)

/// Collapse into latent data keeps the identity: `D`'s handle slot is parked (not freed, generation
/// unchanged) and every relation view naming D goes dormant under it (rel_go_dormant()). Returns the
/// slot id to keep on the latent entry, or 0 when D never had a handle.
/proc/entity_handle_park(datum/D)
	var/id = D.handle_slot
	if(!id)
		return 0
	rel_go_dormant(D)
	if(slot_names(id, D))
		handle_data[id] = null
		handle_types[id] = null
		handle_ta[id] = null
		handle_ib[id] = null
		handle_parked[id] = TRUE
	D.handle_slot = 0
	return id

/// The re-materialized `D` takes over parked slot `id`: every old handle to the collapsed thing
/// resolves to D again, and its dormant relation views re-link (rel_wake()).
/proc/entity_handle_unpark(datum/D, id)
	if(!id || !handle_parked[id])
		return FALSE
	if(D.handle_slot)
		slot_release(D)
	handle_parked -= id
	slot_bind(id, D)
	rel_wake(D, id)
	return TRUE

/// A parked slot whose latent thing is gone for good (discarded, deleted as data): the slot is
/// freed and its generation bumped, and its dormant views are dropped.
/proc/entity_handle_release_parked(id)
	if(!id || !handle_parked[id])
		return
	slot_free(id)
	GLOB.rel_dormant -= id

/// The datum slot `id` names, or null when it was deleted, parked, or freed. A slot whose datum BYOND collected without qdel() is freed and
/// reported (a handle is not a reference: when it was the only thing naming its target, BYOND freed the target at once -- that var owns what it
/// names).
/proc/slot_resolve(id)
	READS_FROM() // the slot lookup behind handle_get(): identity bookkeeping, not reactive state
	var/datum/D = slot_datum(id)
	if(!D)
		if(!slot_taken(id) || handle_parked[id])
			return null
		var/list/types = handle_types
		var/target_type = id <= length(types) ? types[id] : null
		if(!ispath(target_type, /datum/handle_sentinel))
			entity_handle_collected_report(target_type)
		slot_free(id)
		return null
	if(QDELETED(D))
		return null
	return D

/// The handles that are not slot texts: a turf's (its key, then "#generation" once its z-level was released), a client's ("@ckey") and the older
/// "[0x...]" turf ref. Anything else (a stale slot text, junk) names nothing.
/proc/resolve_handle_keyed(h)
	READS_FROM() // the keyed form of handle_get(): identity bookkeeping, not reactive state
	switch(text2ascii(h))
		if(91) // "[": a turf's ref and its z-level's generation
			var/ref_hash = findtext(h, "#")
			var/turf/ref_turf = locate(ref_hash ? copytext(h, 1, ref_hash) : h)
			if(!isturf(ref_turf))
				return null
			if(ref_hash && text2num(copytext(h, ref_hash + 1)) != relation_z_generation(ref_turf.z))
				return null
			return ref_turf
		if(64) // "@ckey#n": a client's ckey and connection
			var/at = findtext(h, "#")
			if(!at)
				return null
			var/client/C = GLOB.directory[copytext(h, 2, at)]
			return (C && C.handle_gen == text2num(copytext(h, at + 1))) ? C : null
	var/packed = GLOB.handle_turf_pos[h]
	if(packed)
		// A plain turf handle seen before: the position is a number. A released z-level (generation moved on) stops it resolving.
		var/z = packed >> 18
		if(relation_z_generation(z))
			return null
		return locate(packed & 511, (packed >> 9) & 511, z)
	var/hash = findtext(h, "#")
	var/key = hash ? copytext(h, 1, hash) : h
	var/turf/T = handle_turf_locate(key)
	if(!isturf(T))
		return null
	// A released and recycled z-level bumps its generation: an old turf handle stops
	// resolving instead of naming a turf of whatever site reuses the level.
	var/gen = hash ? text2num(copytext(h, hash + 1)) : 0
	if(gen != relation_z_generation(T.z))
		return null
	if(!hash && T.x <= 511 && T.y <= 511 && T.z <= 63)
		GLOB.handle_turf_pos[h] = T.x + 512 * (T.y + 512 * T.z)
	return T

/// A handle's target was freed by BYOND without going through qdel() (a
/// qdel'd datum releases its slot in phase 5, so it never gets here): the var
/// holding the handle was its only owner. Reported once per type, with a stack
/// trace naming the reader; a runtime, so a test run fails.
/proc/entity_handle_collected_report(target_type)
	dq_lifecycle_report("HANDLE TARGET COLLECTED WITHOUT QDEL: a handle to [target_type || "an unknown type"] outlived its target, which was freed without qdel() -- the var holding it must be DECLARE_REF(..., OWNED)/DECLARE_REF(..., HELD), not a handle (see the stack for the reader)")

/// TRUE if `h` is shaped like a handle: a whole number, or the text of a turf's or a client's. Says nothing about whether it still resolves.
/proc/is_entity_handle(h)
	var/static/regex/shape = regex(@"^(\d+t\d+:\d+:\d+(#\d+)?|\[0x[0-9a-fA-F]+\](#\d+)?|@\w+)$")
	if(isnum(h))
		return h > 0 && h == round(h)
	return istext(h) && shape.Find(h)

/// qdel()s whatever handle `h` names, if it still exists (QDEL_IN's deferred form).
/proc/qdel_handle(h)
	var/datum/D = handle_get(h)
	if(D)
		spent(D)

// ---------------------------------------------------------------- weak arguments
//
// Every deferred record in the scheduler (timers and their keyed/real-time forms, I/O
// callbacks, timed actions) holds its datum arguments as handles, never as
// references: a record can outlive what it names without keeping it alive (a
// strong ref in a pending timer was a hard delete). capture_args() converts
// at record time, resolve_captured() at fire time; a deleted argument drops
// the call with a log_qdel() line. Synchronous paths never capture.
//
// Captured deeply: every datum anywhere in the arguments -- an argument, a list member, an assoc
// value, at any depth -- becomes a handle marker, list(CAPTURED_MARK, handle), in a copy of the
// list that held it. A datum used as an assoc *key* can't be re-keyed without losing its value,
// so capture refuses it (reported): pass the pair as a value instead. A list holding no datum is
// kept as is (not copied).

#define CAPTURED_MARK "\[om-handle]"
#define CAPTURE_MAX_DEPTH 8

/// Captures `call_args`' datums as handles, deeply. Returns list(captured, positions): positions
/// are the argument indexes holding a handle or a list with handles in it. Null when an argument
/// is already deleted or can't be captured (a datum assoc key).
/proc/capture_args(list/call_args, nulls_for_gone = FALSE)
	var/list/captured = call_args ? call_args.Copy() : null
	var/list/positions = null
	for(var/i in 1 to length(captured))
		var/list/result = capture_value(captured[i], 0, nulls_for_gone)
		if(!result)
			return null
		if(result[2])
			captured[i] = result[1]
			LAZYADD(positions, i)
	return list(captured, positions)

/// list(captured value, changed) for one value, or null when it can't be captured.
/proc/capture_value(value, depth, nulls_for_gone = FALSE)
	if(isdatum(value))
		var/h = handle_of(value)
		if(isnull(h))
			if(nulls_for_gone)
				return list(null, FALSE) // already deleted: passed as null, like one deleted later
			return null
		return list(list(CAPTURED_MARK, h), TRUE)
	if(!islist(value))
		return list(value, FALSE)
	if(depth >= CAPTURE_MAX_DEPTH)
		OWN_REPORT("capture_args: an argument nests lists deeper than [CAPTURE_MAX_DEPTH]")
		return null
	var/list/L = value
	var/list/copy = null
	for(var/j in 1 to length(L))
		var/key = L[j]
		if(isdatum(key) && !isnull(L[key]))
			var/datum/K = key
			OWN_REPORT("capture_args: a deferred call's argument uses [K.type] as an assoc key; pass it as a value")
			return null
		var/list/key_result = capture_value(key, depth + 1, nulls_for_gone)
		if(!key_result)
			return null
		var/assoc = (istext(key) || isdatum(key)) ? L[key] : null
		var/list/value_result = isnull(assoc) ? null : capture_value(assoc, depth + 1, nulls_for_gone)
		if(!isnull(assoc) && !value_result)
			return null
		if(key_result[2] || value_result?[2])
			if(!copy)
				copy = L.Copy()
			if(key_result[2])
				copy[j] = key_result[1]
			else if(value_result?[2])
				copy[key] = value_result[1]
	if(copy)
		return list(copy, TRUE)
	return list(L, FALSE)

/// A deferred call as data: the callee and every datum argument held as handles (deeply), so a
/// stored call never keeps what it names alive -- the replacement for CALLBACK / /datum/callback,
/// whose strong references were invisible to ownership. Returns list(callee handle or null for a
/// global proc, proc ref, captured args, positions), or null when an argument is already gone.
/// Store it in any var; run it with deferred_run(). New code takes then =, owner = and with = and calls after(owner, 0, then, with = ...).
/proc/deferred_call(datum/target, proc_ref, ...)
	var/list/call_args = length(args) > 2 ? args.Copy(3) : null
	var/list/capture = call_args ? capture_args(call_args) : list(null, null)
	if(!capture)
		return null
	var/callee_handle = null
	if(target)
		callee_handle = handle_of(target)
		if(isnull(callee_handle))
			return null
	return list(callee_handle, proc_ref, capture[1], capture[2])

/// Runs an deferred_call() spec with its stored arguments followed by `...`. Returns what the proc
/// returned, or null when the target or a captured argument no longer exists (the call is dropped).
/proc/deferred_run(list/spec, ...)
	if(!islist(spec) || length(spec) != 4)
		return null
	var/datum/target = null
	if(spec[1])
		target = handle_get(spec[1])
		if(!target)
			return null
	var/list/stored = spec[3]
	var/list/call_args = stored ? stored.Copy() : list()
	if(spec[4] && !resolve_captured(call_args, spec[4]))
		return null
	if(length(args) > 1)
		call_args += args.Copy(2)
	if(target)
		return call(target, spec[2])(arglist(call_args))
	return call(spec[2])(arglist(call_args))

/// Resolves captured handles in place. FALSE if any is gone (or, with `nulls_for_gone`, passes
/// null for it instead: cleanup that must still run). The record keeps its own copy.
/proc/resolve_captured(list/captured, list/positions, nulls_for_gone = FALSE)
	for(var/i in positions)
		var/list/result = resolve_captured_value(captured[i], nulls_for_gone)
		if(!result)
			return FALSE
		captured[i] = result[1]
	return TRUE

/// list(resolved value) for one captured value, or null when a handle no longer resolves.
/proc/resolve_captured_value(value, nulls_for_gone)
	if(!islist(value))
		return list(value)
	var/list/L = value
	if(length(L) == 2 && L[1] == CAPTURED_MARK)
		var/datum/D = handle_get(L[2])
		if(!D)
			if(!nulls_for_gone)
				return null
			GLOB.handle_resolve_nulled++
		return list(D)
	var/list/out = L.Copy()
	for(var/j in 1 to length(out))
		var/key = out[j]
		var/assoc = istext(key) ? out[key] : null
		if(islist(key))
			var/list/key_result = resolve_captured_value(key, nulls_for_gone)
			if(!key_result)
				return null
			out[j] = key_result[1]
		else if(islist(assoc))
			var/list/value_result = resolve_captured_value(assoc, nulls_for_gone)
			if(!value_result)
				return null
			out[key] = value_result[1]
	return list(out)
