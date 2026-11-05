// Slots: the integer identity of a datum that something else names.
//
// A datum gets a slot lazily, the first time a relation names it (an owner stamp, a reverse index row, a key index, a watcher) or a handle is
// taken to it, and keeps it until it is destroyed (phase 5 of the destroy transaction frees it). A slot is a whole number, so it keys an alist and
// compares without making a string: it replaces the old own_key() text (gone), the "<scramble>:<id>:<type>" text built from the ref, which BYOND hashed badly,
// which was recycled with the ref (a stale key could name a newer datum), and which had to be parsed and locate()d to find its datum again.
//
// The slot table holds no reference to the datum. Per slot it keeps the two numbers of the datum's address (handle_ta, handle_ib), which
// slot_datum() turns back into the datum with one locate() and then checks (the datum names the slot back), and a generation (handle_gens).
// Freeing a slot bumps its generation, so a handle taken before never resolves to what reuses the slot (the ABA case). The generation is five
// bits, so a slot is freed 31 times and then retired for good: a handle's generation never wraps and a retired slot is never handed out.
//
// A handle is slot + SLOT_SPAN * generation, one number exact below 2^24 (BYOND numbers are 32-bit floats; the ~1.05M instances of a live
// world do not need a slot each, only what is named: SLOT_MAX slots can be live or retired at once, and running out is reported). Two other
// forms exist because the datum has no slot to take: a turf's slot is the negative of its packed position (its identity is where it is, and
// ChangeTurf() resets its vars), and a turf's or client's handle is the text ref_token() makes. handle_of() / handle_get() are the one pair for all
// of them; ref_token() is the text form, for a UI that needs a string.

/// Slots live or retired at once: a handle packs the slot into 19 bits.
#define SLOT_MAX (SLOT_SPAN - 1)

// The tables are real BYOND globals, made by the first slot_make(): the kernel creates its systems in Genesis, before the GLOB controller exists, and a
// system owns children (a datum named by its owner's slot), and a managed global would be wiped by its initializer after being used.
/// Per handle slot: the generation (0 to SLOT_GEN_MAX; above it the slot is retired).
GLOBAL_REAL(handle_gens, /list)
/// Per handle slot: the type of the datum it names (for the collected-without-qdel report).
GLOBAL_REAL(handle_types, /list)
/// Slots free to reuse, the last freed on top.
GLOBAL_REAL(handle_free, /list)
/// Per handle slot: the type part of the target's address (the number in "[0x<type><id>]"), or null while the slot is free or parked.
GLOBAL_REAL(handle_ta, /list)
/// Per handle slot: the id part of the target's address (the last six hex digits of its ref).
GLOBAL_REAL(handle_ib, /list)
/// Slot -> the target's raw ref text, for the rare ref that is not "[0x<type><id>]" (every other slot reads null).
GLOBAL_REAL(handle_raw, /alist)
/// Slots parked for a thing that collapsed into latent data (containment.md sec 4.5): they resolve to null until the entry re-materializes into
/// the same slot (entity_handle_unpark()).
GLOBAL_REAL(handle_parked, /alist)

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

/// D's slot: its whole-number identity, made on first use. 0 for anything that is not a datum (or a turf outside the packable positions), and
/// when every slot is in use (reported).
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

/// Takes a slot for D, which has none.
/proc/slot_make(datum/D)
	if(isnull(handle_gens))
		handle_gens = list()
		handle_types = list()
		handle_free = list()
		handle_ta = list()
		handle_ib = list()
		handle_raw = alist()
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
		handle_types.len++
		handle_ta.len++
		handle_ib.len++
		gens[id] = 0
	slot_bind(id, D)
	return id

/// Slot `id` names `D` from now on: its address as two numbers, its type, and D's own back-pointer.
/proc/slot_bind(id, datum/D)
	var/ref_text = "\ref[D]"
	var/n = length(ref_text)
	// "[0x" + type digits + 6 id digits + "]"; anything else is kept as it is.
	if(n < 11 || text2ascii(ref_text, 3) != 120)
		handle_ta[id] = null
		handle_ib[id] = null
		handle_raw[id] = ref_text
	else
		handle_ta[id] = text2num(copytext(ref_text, 4, n - 6), 16)
		handle_ib[id] = text2num(copytext(ref_text, n - 6, n), 16)
		handle_raw -= id
	handle_types[id] = D.type
	D.handle_slot = id

/// The datum slot `id` names, or null (a free or parked slot, a datum BYOND freed, a slot reused by another datum). Never reports and never
/// changes a slot. A turf's slot is a position.
/proc/slot_datum(id)
	READS_FROM()
	if(!isnum(id) || !id)
		return null
	if(id < 0)
		var/code = -id
		return locate(code & 511, (code >> 9) & 511, code >> 18)
	if(id > length(handle_ta))
		return null
	var/ta = handle_ta[id]
	var/datum/D
	if(!isnull(ta))
		D = locate("\[0x[num2text(ta, 1, 16)][num2text(handle_ib[id], 6, 16)]\]")
	else
		var/raw = handle_raw[id]
		if(raw)
			D = locate(raw)
	if(!isdatum(D) || D.handle_slot != id)
		return null
	return D

/// TRUE while slot `id` is taken: bound to a datum, or parked for a latent one.
/proc/slot_taken(id)
	return id > 0 && id <= length(handle_ta) && (!isnull(handle_ta[id]) || handle_raw[id] || handle_parked[id])

/// Frees slot `id`: every handle to it stops resolving (the generation moves on) and it is free to reuse, until its generation reaches
/// SLOT_GEN_MAX, when it is retired instead.
/proc/slot_free(id)
	var/list/gens = handle_gens
	handle_ta[id] = null
	handle_ib[id] = null
	handle_raw -= id
	handle_parked -= id
	slot_texts_forget(id)
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

/// TRUE when slot `id`'s address is `D`'s (D may be mid-delete and no longer name the slot back).
/proc/slot_names(id, datum/D)
	var/ref_text = "\ref[D]"
	var/n = length(ref_text)
	var/ta = handle_ta[id]
	if(isnull(ta))
		return handle_raw[id] == ref_text
	return n >= 11 && ta == text2num(copytext(ref_text, 4, n - 6), 16) && handle_ib[id] == text2num(copytext(ref_text, n - 6, n), 16)

/// Slot `id` names `successor` now (replace_with(): old handles resolve to the successor), if it names `original`.
/proc/slot_rebind(datum/original, datum/successor)
	var/id = original.handle_slot
	if(!id || successor.handle_slot || !slot_names(id, original))
		return FALSE
	original.handle_slot = 0
	slot_bind(id, successor)
	return TRUE

/// The handle to `D`: slot + SLOT_SPAN * generation for a datum with a slot, the text ref_token() makes for a turf or a client. Null for a deleted
/// datum or a non-datum. Store it in any var; handle_get() reads it back.
/proc/handle_of(datum/D)
	READS_FROM() // the same identity bookkeeping as slot_of()
	if(isturf(D) || isclient(D))
		return ref_token(D)
	if(!isdatum(D) || QDELETED(D))
		return null
	var/id = D.handle_slot || slot_make(D)
	if(!id)
		return null
	return id + SLOT_SPAN * handle_gens[id]

/// The datum handle `h` names (from handle_of(), or the text of ref_token()), or null once it was deleted, whatever now uses its slot.
/proc/handle_get(h)
	READS_FROM() // turns a handle back into the datum: identity bookkeeping, not reactive state
	if(!isnum(h))
		return resolve_token(h)
	var/id = h & (SLOT_SPAN - 1)
	if(!id || id > length(handle_gens) || handle_gens[id] != (h >> 19))
		return null
	return slot_resolve(id)
