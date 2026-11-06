// Slots: the integer identity of a datum that something else names.
//
// A datum gets a slot lazily, the first time a relation names it (an owner stamp, a reverse index row, a key index, a watcher) or a handle is
// taken to it, and keeps it until it is destroyed (phase 5 of the destroy transaction frees it). A slot is a whole number, so it keys an alist and
// compares without making a string. It replaces the old own_key() text, which BYOND hashed badly, which was recycled with the ref (a stale key could
// name a newer datum), and which had to be parsed and locate()d to find its datum again.
//
// The slot table holds the datum (handle_data[slot]), so slot_datum() is one list read: no locate(), no string, no address arithmetic. That is
// what lets a teardown walk its reverse index in integers. The price is the ownership rule that comes with it: a datum that something names is
// deleted with qdel(), which frees its slot (phase 5) and clears everything that names it first. A datum BYOND frees any other way (dropped
// with no qdel(), or del()) is a leak: the table still holds it, slot_leaks() finds it, and slot_leak_report() logs it by type. Nothing here
// ever hard-deletes, and nothing sweeps for it on a timer.
//
// Freeing a slot bumps its generation, so a handle taken before never resolves to what reuses the slot (the ABA case). The generation is five
// bits, so a slot is freed 31 times and then retired for good: a handle's generation never wraps and a retired slot is never handed out.
//
// A handle is slot + SLOT_SPAN * generation, one number exact below 2^24 (BYOND numbers are 32-bit floats; the ~1.05M instances of a live
// world do not need a slot each, only what is named: SLOT_MAX slots can be live or retired at once, and running out is reported). Two other
// forms exist because the datum has no slot to take: a turf's slot is the negative of its packed position (its identity is where it is, and
// ChangeTurf() resets its vars), and a turf's or client's handle is the text handle_keyed_of() makes. handle_of() / handle_get() are the one pair for
// all of them.
//
// One exception holds a datum weakly: a /datum/handle_sentinel (a stack canary), whose whole purpose is to be freed by BYOND when the stack that
// held it ends. Its slot keeps the two numbers of its address (handle_ta, handle_ib) and slot_datum() locate()s it.

/// Slots live or retired at once: a handle packs the slot into 19 bits.
#define SLOT_MAX (SLOT_SPAN - 1)

// The tables are real BYOND globals, made by the first slot_make(): the kernel creates its systems in Genesis, before the GLOB controller exists, and a
// system owns children (a datum named by its owner's slot), and a managed global would be wiped by its initializer after being used.
/// Per handle slot: the generation (0 to SLOT_GEN_MAX; above it the slot is retired).
GLOBAL_REAL(handle_gens, /list)
/// Per handle slot: the datum it names, held strongly; null while the slot is free, parked, weak, or its datum was freed with del().
GLOBAL_REAL(handle_data, /list)
/// Per handle slot: the type of the datum it names (for the leak report).
GLOBAL_REAL(handle_types, /list)
/// Slots free to reuse, the last freed on top.
GLOBAL_REAL(handle_free, /list)
/// Per weak slot (a sentinel): the type part of the target's address (the number in "[0x<type><id>]"), or null.
GLOBAL_REAL(handle_ta, /list)
/// Per weak slot: the id part of the target's address (the last six hex digits of its ref).
GLOBAL_REAL(handle_ib, /list)
/// Slots parked for a thing that collapsed into latent data (containment.md sec 4.5): they resolve to null until the entry re-materializes into
/// the same slot (entity_handle_unpark()).
GLOBAL_REAL(handle_parked, /alist)
/// Slot -> leak count by the last slot_leak_report(): the datum type's text -> how many, logged and kept for the memory report.
GLOBAL_REAL(slot_leak_counts, /list)

/// The datum's slot, 0 until slot_of() is first called on it (a turf's is its position and is never stored).
/datum/var/tmp/handle_slot = 0

/// A turf's slot: the negative of its position packed as x + 512 * (y + 512 * z). Turfs are never deleted, and a position says the same turf
/// after ChangeTurf(); a level of more than 511 by 511, or a z over 63, has no slot (reported).
/proc/slot_of_turf(turf/T)
	READS_FROM()
	if(T.x > 511 || T.y > 511 || T.z > 63 || T.z < 1)
		dq_lifecycle_report("SLOT: the turf at [T.x],[T.y],[T.z] is outside the 511x511x63 positions a turf slot packs")
		return 0
	return -(T.x + 512 * (T.y + 512 * T.z))

/// D's slot, made on first use: its whole-number identity. 0 for anything that is not a datum (or a turf outside the packable positions), and when
/// every slot is in use or D is already past having its slot released (reported).
/proc/slot_of(datum/D)
	READS_FROM() // a slot is the datum's stable id: the table it reads is identity bookkeeping, not state a draw or condition depends on
	if(isturf(D))
		return slot_of_turf(D)
	if(!isdatum(D))
		return 0
	. = D.handle_slot
	if(.)
		return
	return slot_make(D)

/// D's slot if it has one, else 0; never makes one. For a read or a removal, which names nothing that was never indexed.
/proc/slot_known(datum/D)
	READS_FROM()
	if(isturf(D))
		return slot_of_turf(D)
	return isdatum(D) ? D.handle_slot : 0

/// Takes a slot for D, which has none.
/proc/slot_make(datum/D)
	// The table holds D, so a datum that is past phase 5 (its slot already released) must not be named again: the new slot would keep it alive for good.
	if(D.destroy_phase >= LIFECYCLE_PHASE_SLOTS_RELEASED)
		dq_lifecycle_report("SLOT: a [D.type] was named after its destroy transaction released its slot; the table would hold it for good")
		return 0
	if(isnull(handle_gens))
		handle_gens = list()
		handle_data = list()
		handle_types = list()
		handle_free = list()
		handle_ta = list()
		handle_ib = list()
		handle_parked = alist()
	var/list/gens = handle_gens
	var/list/free = handle_free
	var/id
	if(length(free))
		id = free[length(free)]
		free.len--
	else
		id = length(gens) + 1
		if(id > SLOT_MAX)
			dq_lifecycle_report("SLOT: all [SLOT_MAX] slots are live or retired; a [D.type] cannot be named")
			return 0
		gens.len++
		handle_data.len++
		handle_types.len++
		handle_ta.len++
		handle_ib.len++
		gens[id] = 0
	slot_bind(id, D)
	return id

/// Slot `id` names `D` from now on: D itself (its address instead, for a sentinel), its type, and D's own back-pointer.
/proc/slot_bind(id, datum/D)
	if(istype(D, /datum/handle_sentinel))
		var/ref_text = "\ref[D]"
		var/n = length(ref_text)
		// "[0x" + type digits + 6 id digits + "]".
		handle_data[id] = null
		handle_ta[id] = n >= 11 ? text2num(copytext(ref_text, 4, n - 6), 16) : null
		handle_ib[id] = n >= 11 ? text2num(copytext(ref_text, n - 6, n), 16) : null
	else
		handle_data[id] = D
		handle_ta[id] = null
		handle_ib[id] = null
	handle_types[id] = D.type
	D.handle_slot = id

/// The datum slot `id` names, or null (a free or parked slot, a datum BYOND freed with del()). Never reports and never changes a slot. A turf's slot
/// is a position.
/proc/slot_datum(id)
	READS_FROM()
	if(!isnum(id) || !id)
		return null
	if(id < 0)
		var/code = -id
		return locate(code & 511, (code >> 9) & 511, code >> 18)
	if(id > length(handle_data))
		return null
	var/datum/D = handle_data[id]
	if(D)
		return D
	var/ta = handle_ta[id]
	if(isnull(ta))
		return null
	D = locate("\[0x[num2text(ta, 1, 16)][num2text(handle_ib[id], 6, 16)]\]")
	return (isdatum(D) && D.handle_slot == id) ? D : null

/// TRUE while slot `id` is taken: bound to a datum (or a sentinel's address), or parked for a latent one.
/proc/slot_taken(id)
	return id > 0 && id <= length(handle_types) && (!isnull(handle_types[id]) || handle_parked[id])

/// Frees slot `id`: every handle to it stops resolving (the generation moves on) and it is free to reuse, until its generation reaches
/// SLOT_GEN_MAX, when it is retired instead.
/proc/slot_free(id)
	var/list/gens = handle_gens
	handle_data[id] = null
	handle_types[id] = null
	handle_ta[id] = null
	handle_ib[id] = null
	handle_parked -= id
	gens[id]++
	if(gens[id] > SLOT_GEN_MAX)
		return // the generation 32 no handle can carry: nothing ever matches this slot again, and it is not offered for reuse
	handle_free += id

/// How many slots have been retired (the generation reached SLOT_GEN_MAX and the slot left circulation). A scan, for tests and the memory report.
/proc/slots_retired()
	. = 0
	for(var/gen in handle_gens)
		if(gen > SLOT_GEN_MAX)
			.++

/// Lifecycle phase 5: frees `D`'s slot. Every handle to it stops resolving.
/proc/slot_release(datum/D)
	var/id = D.handle_slot
	if(!id)
		return
	D.handle_slot = 0
	if(slot_taken(id) && slot_names(id, D))
		slot_free(id)

/// TRUE when slot `id` names `D` (D may be mid-delete and no longer name the slot back).
/proc/slot_names(id, datum/D)
	if(!isnull(handle_data[id]))
		return handle_data[id] == D
	var/ta = handle_ta[id]
	if(isnull(ta))
		return FALSE
	var/ref_text = "\ref[D]"
	var/n = length(ref_text)
	return n >= 11 && ta == text2num(copytext(ref_text, 4, n - 6), 16) && handle_ib[id] == text2num(copytext(ref_text, n - 6, n), 16)

/// Slot `id` names `successor` now (replace_with(): old handles resolve to the successor), if it names `original`.
/proc/slot_rebind(datum/original, datum/successor)
	var/id = original.handle_slot
	if(!id || successor.handle_slot || !slot_names(id, original))
		return FALSE
	original.handle_slot = 0
	slot_bind(id, successor)
	return TRUE

/// The handle to `D`: slot + SLOT_SPAN * generation for a datum with a slot, the text handle_keyed_of() makes for a turf or a client. Null for a deleted
/// datum or a non-datum. Store it in any var; handle_get() reads it back.
/proc/handle_of(datum/D)
	READS_FROM() // the same identity bookkeeping as slot_of()
	if(isturf(D) || isclient(D))
		return handle_keyed_of(D)
	if(!isdatum(D) || QDELETED(D))
		return null
	var/id = D.handle_slot || slot_make(D)
	if(!id)
		return null
	return id + SLOT_SPAN * handle_gens[id]

/// The datums slots `slots` name, as a new list: a slot with no datum (freed, parked) is skipped. Null for none.
/proc/slot_datums(list/slots)
	. = list()
	for(var/slot in slots)
		var/datum/D = slot_datum(slot)
		if(D)
			. += D

/// A handle as text, for a text key, an href or a log line that is parsed back: the whole number, never the 6-digit "1.04858e+06" form that "[h]" gives
/// a number from 1e6 on (a handle reaches 2^24). A turf's or a client's handle is already text and passes through. handle_get() reads either back.
/proc/handle_text(h)
	READS_FROM() // text of a handle: identity bookkeeping, not reactive state
	if(isnum(h))
		return num2text(h, 16)
	return h

/// The datum handle `h` names (from handle_of(), a number or the text of one), or null once it was deleted, whatever now uses its slot.
/proc/handle_get(h)
	READS_FROM() // turns a handle back into the datum: identity bookkeeping, not reactive state
	if(istext(h))
		var/static/regex/whole = regex(@"^\d+$")
		if(!whole.Find(h))
			return resolve_handle_keyed(h) // a turf's or a client's handle, or junk
		h = text2num(h)
	if(!isnum(h))
		return null
	var/id = h & (SLOT_SPAN - 1)
	if(!id || id > length(handle_gens) || handle_gens[id] != (h >> 19))
		return null
	return slot_resolve(id)

// ---------------------------------------------------------------- leaks

/// How many references slot_refs() reports for a datum that only the slot table holds: measured once on a probe, so the number is never a guess.
/proc/slot_only_refs()
	var/static/baseline
	if(isnull(baseline))
		var/id = slot_probe_make()
		baseline = slot_refs(id)
		var/datum/probe = handle_data[id]
		probe.handle_slot = 0
		probe = null
		slot_free(id)
	return baseline

/// A datum nothing but the slot table references (a probe for slot_only_refs()).
/datum/slot_probe_datum

/// Names a probe and lets go of it, so the slot table alone holds it when this returns. Returns its slot.
/proc/slot_probe_make()
	var/datum/slot_probe_datum/probe = new
	return slot_make(probe)

/// The references to slot `id`'s datum, counted in a frame of its own (its local, and the table's); 0 for a slot with no live datum.
/proc/slot_refs(id)
	var/datum/D = handle_data[id]
	if(isnull(D) || QDELETED(D))
		return 0
	return refcount(D)

/// Every slot whose datum the table alone keeps alive (nothing else names it, and it was never qdel()ed), and every slot whose datum BYOND freed
/// with del(), as a list of the slot numbers. One pass over the table: called on request (a test, the round's end), never on a timer.
/proc/slot_leaks()
	. = list()
	if(isnull(handle_data))
		return
	var/only = slot_only_refs()
	for(var/id in 1 to length(handle_data))
		if(!slot_taken(id) || handle_parked[id])
			continue
		if(!isnull(handle_data[id]))
			var/refs = slot_refs(id)
			if(refs && refs <= only)
				. += id
		else if(isnull(handle_ta[id]))
			. += id // the datum was freed with del(): the slot is still taken

/// slot_leaks() by type: type text -> count. Logs one line per type (never a hard delete; the datum and its slot stay, so the holder can be found).
/proc/slot_leak_report(log = TRUE)
	var/list/leaks = slot_leaks()
	var/list/by_type = list()
	for(var/id in leaks)
		var/type_text = "[handle_types[id]]"
		by_type[type_text] = (by_type[type_text] || 0) + 1
	slot_leak_counts = by_type
	if(log)
		for(var/type_text in by_type)
			log_world("SLOT LEAK: [by_type[type_text]] x [type_text] dropped without qdel() (the slot table still holds them)")
	return by_type
