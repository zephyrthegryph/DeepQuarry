// Handles and weak arguments (the time engine: doc/rewrite/framework_gaps.md C1).
//
// OM handles: om_handle(D) -> "id:gen", om_resolve(h) -> D or null. The same model as the Rust core's handles: a slot table with a
// generation per slot, no per-target datum. A deleted datum's slot is freed and its generation bumped, so a stale handle never resolves to
// whatever reuses the id. Every deferred record in the engine (timers and their keyed and real-time forms, I/O callbacks, timed actions)
// holds its datum arguments as handles, never as references: a record can outlive what it names without keeping it alive.

// ---------------------------------------------------------------- handles
//
// A slot table: slot id -> the datum's weak key (own_key(): not its ref text, because retained
// ref strings slow BYOND down), plus a generation per slot.
// The table holds text, never the datum, so a handle doesn't keep its target
// alive: a datum BYOND collects without qdel() (a dropped species, a stack
// canary) simply stops resolving, like one that was qdel()ed.

GLOBAL_LIST_EMPTY(om_handle_slots)
GLOBAL_LIST_EMPTY(om_handle_gens)
/// Per handle slot: the type of the datum it names (for the collected-without-qdel report).
GLOBAL_LIST_EMPTY(om_handle_types)
GLOBAL_LIST_EMPTY(om_handle_free)

/// The datum's handle slot, 0 until om_handle() is first called on it.
/datum/var/tmp/om_hid = 0

/// A handle to `D`: "id:gen". Null for a deleted datum or a non-datum.
/// A turf's handle is its ref text ("[0x...]"): turfs are never deleted and a turf's
/// ref is its position, so it survives ChangeTurf() (which resets the turf's vars).
/// A client's is "@ckey", resolved through GLOB.directory.
/proc/om_handle(datum/D)
	if(isturf(D))
		var/turf/T = D
		return "[REF(T)]#[om_z_generation(T.z)]"
	if(isclient(D))
		var/client/C = D
		return "@[C.ckey]" // a client is its ckey: it reads null while that player is disconnected
	if(!isdatum(D) || QDELETED(D))
		return null
	var/list/slots = GLOB.om_handle_slots
	var/list/gens = GLOB.om_handle_gens
	var/id = D.om_hid
	if(!id)
		var/list/free = GLOB.om_handle_free
		if(length(free))
			id = free[length(free)]
			free.len--
		else
			slots.len++
			gens.len++
			id = length(slots)
			gens[id] = 0
		slots[id] = own_key(D)
		var/list/types = GLOB.om_handle_types
		if(length(types) < id)
			types.len = id
		types[id] = D.type
		D.om_hid = id
	return "[id]:[gens[id]]"

/// The handle `D` already has, even while `D` is being deleted (until phase 5 releases it), or null
/// if it never had one. Never allocates. For taking a dying datum out of a handle-keyed list.
/proc/om_handle_of(datum/D)
	if(isturf(D) || isclient(D))
		return om_handle(D)
	if(!isdatum(D))
		return null
	var/id = D.om_hid
	return id ? "[id]:[GLOB.om_handle_gens[id]]" : null

/// TRUE if handle `h` names `D`, even while `D` is being deleted (until phase 5
/// releases its slot). A handle accessor (`owner()` = om_resolve(owner_handle))
/// reads null once its target is QDELETED, so `owner() == src` is FALSE inside
/// src's own teardown: compare with om_handle_is(owner_handle, src) there.
/proc/om_handle_is(h, datum/D)
	if(!h || !D)
		return FALSE
	return h == om_handle_of(D)

/// A handle slot parked for a thing that collapsed into latent data (containment.md sec 4.5): it
/// resolves to null until the entry re-materializes into the same slot (om_handle_unpark()).
#define OM_HANDLE_PARKED "\[latent]"

/// Collapse into latent data keeps the identity: `D`'s handle slot is parked (not freed, generation
/// unchanged) and every relation view naming D goes dormant under it (rel_go_dormant()). Returns the
/// slot id to keep on the latent entry, or 0 when D never had a handle.
/proc/om_handle_park(datum/D)
	var/id = D.om_hid
	if(!id)
		return 0
	rel_go_dormant(D)
	var/list/slots = GLOB.om_handle_slots
	if(id <= length(slots) && slots[id] == own_key(D))
		slots[id] = OM_HANDLE_PARKED
	D.om_hid = 0
	return id

/// The re-materialized `D` takes over parked slot `id`: every old handle to the collapsed thing
/// resolves to D again, and its dormant relation views re-link (rel_wake()).
/proc/om_handle_unpark(datum/D, id)
	var/list/slots = GLOB.om_handle_slots
	if(!id || id > length(slots) || slots[id] != OM_HANDLE_PARKED)
		return FALSE
	if(D.om_hid)
		om_handle_release(D)
	slots[id] = own_key(D)
	var/list/types = GLOB.om_handle_types
	if(length(types) >= id)
		types[id] = D.type
	D.om_hid = id
	rel_wake(D, id)
	return TRUE

/// A parked slot whose latent thing is gone for good (discarded, deleted as data): the slot is
/// freed and its generation bumped, and its dormant views are dropped.
/proc/om_handle_release_parked(id)
	var/list/slots = GLOB.om_handle_slots
	if(!id || id > length(slots) || slots[id] != OM_HANDLE_PARKED)
		return
	slots[id] = null
	GLOB.om_handle_gens[id]++
	GLOB.om_handle_free += id
	GLOB.rel_dormant -= "[id]"

/// The datum a handle names, or null if it has been deleted (whatever now uses its id).
/proc/om_resolve(h)
	if(!istext(h))
		return null
	switch(text2ascii(h))
		if(91) // "[": a turf's ref and its z-level's generation (om_handle())
			var/hash = findtext(h, "#")
			var/turf/T = locate(hash ? copytext(h, 1, hash) : h)
			if(!isturf(T))
				return null
			// A released and recycled z-level bumps its generation: an old turf handle stops
			// resolving instead of naming a turf of whatever site reuses the level.
			if(hash && text2num(copytext(h, hash + 1)) != om_z_generation(T.z))
				return null
			return T
		if(64) // "@": a client's ckey
			return GLOB.directory[copytext(h, 2)]
	var/sep = findtext(h, ":")
	if(!sep)
		return null
	var/id = text2num(copytext(h, 1, sep))
	var/list/slots = GLOB.om_handle_slots
	if(!id || id > length(slots))
		return null
	if(GLOB.om_handle_gens[id] != text2num(copytext(h, sep + 1)))
		return null
	var/ref = slots[id]
	if(!ref || ref == OM_HANDLE_PARKED)
		return null
	var/datum/D = own_locate(ref)
	if(!isdatum(D) || D.om_hid != id)
		// Collected without qdel(); a new datum may even have the ref now. Free the slot.
		// A handle is not a reference: when it was the only thing naming its
		// target, BYOND freed the target at once (a nullspace holder turned into
		// a handle by the LC-refs sweep). That var owns what it names.
		var/list/types = GLOB.om_handle_types
		om_handle_collected_report(id <= length(types) ? types[id] : null)
		slots[id] = null
		GLOB.om_handle_gens[id]++
		GLOB.om_handle_free += id
		return null
	if(QDELETED(D))
		return null
	return D

/// Lifecycle phase 5: frees `D`'s handle slot. Every handle to it stops resolving.
/// A handle's target was freed by BYOND without going through qdel() (a
/// qdel'd datum releases its slot in phase 5, so it never gets here): the var
/// holding the handle was its only owner. Reported once per type, with a stack
/// trace naming the reader; a runtime, so a test run fails.
/proc/om_handle_collected_report(target_type)
	dq_lifecycle_report("HANDLE TARGET COLLECTED WITHOUT QDEL: a handle to [target_type || "an unknown type"] outlived its target, which was freed without qdel() -- the var holding it must be DECLARE_REF(..., OWNED)/DECLARE_REF(..., HELD), not a handle (see the stack for the reader)")

/proc/om_handle_release(datum/D)
	var/id = D.om_hid
	if(!id)
		return
	D.om_hid = 0
	var/list/slots = GLOB.om_handle_slots
	if(id > length(slots) || slots[id] != own_key(D))
		return
	slots[id] = null
	GLOB.om_handle_gens[id]++
	GLOB.om_handle_free += id

/// TRUE if `h` is text shaped like an OM handle ("id:gen"). Says nothing about
/// whether it still resolves.
/proc/om_is_handle(h)
	var/static/regex/shape = regex(@"^(\d+:\d+|\[0x[0-9a-fA-F]+\](#\d+)?|@\w+)$")
	return istext(h) && shape.Find(h)

/// qdel()s whatever handle `h` names, if it still exists (QDEL_IN's deferred form).
/proc/qdel_handle(h)
	var/datum/D = om_resolve(h)
	if(D)
		spent(D)

// ---------------------------------------------------------------- weak arguments
//
// Every deferred record in the OM (timers and their keyed/real-time forms, I/O
// callbacks, timed actions) holds its datum arguments as OM handles, never as
// references: a record can outlive what it names without keeping it alive (a
// strong ref in a pending timer was a hard delete). capture_args() converts
// at record time, resolve_captured() at fire time; a deleted argument drops
// the call with a log_qdel() line. Synchronous paths never capture.
//
// Captured deeply: every datum anywhere in the arguments -- an argument, a list member, an assoc
// value, at any depth -- becomes a handle marker, list(OM_CAPTURED_MARK, handle), in a copy of the
// list that held it. A datum used as an assoc *key* can't be re-keyed without losing its value,
// so capture refuses it (reported): pass the pair as a value instead. A list holding no datum is
// kept as is (not copied).

#define OM_CAPTURED_MARK "\[om-handle]"
#define OM_CAPTURE_MAX_DEPTH 8

/// Captures `call_args`' datums as handles, deeply. Returns list(captured, positions): positions
/// are the argument indexes holding a handle or a list with handles in it. Null when an argument
/// is already deleted or can't be captured (a datum assoc key).
/proc/capture_args(list/call_args, nulls_for_gone = FALSE)
	var/list/captured = call_args ? call_args.Copy() : null
	var/list/positions = null
	for(var/i in 1 to length(captured))
		var/list/result = om_capture_value(captured[i], 0, nulls_for_gone)
		if(!result)
			return null
		if(result[2])
			captured[i] = result[1]
			LAZYADD(positions, i)
	return list(captured, positions)

/// list(captured value, changed) for one value, or null when it can't be captured.
/proc/om_capture_value(value, depth, nulls_for_gone = FALSE)
	if(isdatum(value))
		var/h = om_handle(value)
		if(isnull(h))
			if(nulls_for_gone)
				return list(null, FALSE) // already deleted: passed as null, like one deleted later
			return null
		return list(list(OM_CAPTURED_MARK, h), TRUE)
	if(!islist(value))
		return list(value, FALSE)
	if(depth >= OM_CAPTURE_MAX_DEPTH)
		OWN_REPORT("om_capture_args: an argument nests lists deeper than [OM_CAPTURE_MAX_DEPTH]")
		return null
	var/list/L = value
	var/list/copy = null
	for(var/j in 1 to length(L))
		var/key = L[j]
		if(isdatum(key) && !isnull(L[key]))
			var/datum/K = key
			OWN_REPORT("om_capture_args: a deferred call's argument uses [K.type] as an assoc key; pass it as a value")
			return null
		var/list/key_result = om_capture_value(key, depth + 1, nulls_for_gone)
		if(!key_result)
			return null
		var/assoc = (istext(key) || isdatum(key)) ? L[key] : null
		var/list/value_result = isnull(assoc) ? null : om_capture_value(assoc, depth + 1, nulls_for_gone)
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
/// Store it in any var; run it with om_run(). Only the om_watch probes still use it (machinery lane): new code takes then =, owner = and with = (after_done()).
/proc/om_callable(datum/target, proc_ref, ...)
	var/list/call_args = length(args) > 2 ? args.Copy(3) : null
	var/list/capture = call_args ? capture_args(call_args) : list(null, null)
	if(!capture)
		return null
	var/callee_handle = null
	if(target)
		callee_handle = om_handle(target)
		if(isnull(callee_handle))
			return null
	return list(callee_handle, proc_ref, capture[1], capture[2])

/// Runs an om_callable() spec with its stored arguments followed by `...`. Returns what the proc
/// returned, or null when the target or a captured argument no longer exists (the call is dropped).
/proc/om_run(list/spec, ...)
	if(!islist(spec) || length(spec) != 4)
		return null
	var/datum/target = null
	if(spec[1])
		target = om_resolve(spec[1])
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
		var/list/result = om_resolve_value(captured[i], nulls_for_gone)
		if(!result)
			return FALSE
		captured[i] = result[1]
	return TRUE

/// list(resolved value) for one captured value, or null when a handle no longer resolves.
/proc/om_resolve_value(value, nulls_for_gone)
	if(!islist(value))
		return list(value)
	var/list/L = value
	if(length(L) == 2 && L[1] == OM_CAPTURED_MARK)
		var/datum/D = om_resolve(L[2])
		if(!D)
			if(!nulls_for_gone)
				return null
			GLOB.om_resolve_nulled++
		return list(D)
	var/list/out = L.Copy()
	for(var/j in 1 to length(out))
		var/key = out[j]
		var/assoc = istext(key) ? out[key] : null
		if(islist(key))
			var/list/key_result = om_resolve_value(key, nulls_for_gone)
			if(!key_result)
				return null
			out[j] = key_result[1]
		else if(islist(assoc))
			var/list/value_result = om_resolve_value(assoc, nulls_for_gone)
			if(!value_result)
				return null
			out[key] = value_result[1]
	return list(out)
