// Latent contents (doc/rewrite/containment.md §4, roadmap C5).
//
// A holder type opts in with `latent_contents = TRUE`. Its contents then pass
// through three stages:
//
//   Declared      a generator (latent_generator(): a spawn list such as a
//                 closet's starts_with). Nothing is rolled. dq_latent_declare()
//                 runs at init and creates only the types that can't be latent.
//   Resolved      /datum/latent_entry records in the holder's ledger: a type,
//                 an optional state blob (the delta), a count and a slot. The
//                 ledger resolves the generator the first time it is built,
//                 i.e. the first time anything asks an exact question (weight,
//                 capacity, "contains X", a move in or out).
//   Materialized  real atoms, made by latent_materialize(): opened, searched,
//                 examined inside, hit by an effect that reaches contents, or
//                 pulled out. Materializing is a ledger move: the entry's count
//                 drops before the atom exists, so nothing materializes twice.
//
// Aggregates (mass, heat capacity, thresholds, tags) and slot capacity count
// entries through per-type data (dq_type_property, the material templates),
// scaled by count, without instances.
//
// Collapse (opt-in, §4.5): latent_collapse() turns a real, simple item back
// into an entry when state_collapse_blockers() is empty and it holds nothing.
//
// Legacy code walks `contents` directly and can't see entries, so a holder
// type is only made latent once its own code goes through this API; the
// generic walkers (get_all_contents, GetAllContents) materialize first, and
// tools/ci/latent_lint.py forbids new raw walks on latent holders.

/// Why the last latent_collapse() refused, for tests and admins.
GLOBAL_VAR(latent_last_refusal)

/// The holder type keeps latent entries (containment.md §4). Type-level.
/atom/var/tmp/latent_contents = FALSE
/// The generator was declared at init (its non-latent types already exist).
/atom/var/tmp/latent_declared = FALSE

/// One group of identical latent things in a holder's slot.
/datum/latent_entry
	/// Type path.
	var/path
	var/count = 0
	/// STATE_FULL blob of one of them, or null for a pristine instance.
	var/list/blob
	var/slot
	/// Unique per holder, like a real thing's entry serial.
	var/serial
	/// Parked OM handle slots of collapsed things in this entry (entity_handle_park()): each one
	/// re-materializes into its old slot, so handles and relation views to it survive the round trip.
	var/list/handles
	/// Bumped on every change, so a stale id is refused (invariant 1).
	var/generation = 0
	/// Merge key: slot, type and state hash.
	var/key
	/// Contribution to the aggregates (count applied).
	var/list/snapshot
	/// Capacity one of them takes in its slot.
	var/unit_cost = 0
	/// The blob captured right after a real collapse (roadmap C10,
	/// containment.md §4.7 "Safety"), set only when the round-trip audit is
	/// on (not for the original declared generator, which was never a real
	/// atom). This is the same list object as `blob` (dq_latent_entry_blob()
	/// mutates and returns its argument in place) at the moment of capture,
	/// so it verifies the entry's own state round-trips through
	/// materialize -> serialize, not a byte-for-byte pre-strip snapshot.
	/// Checked against the next materialize from this entry, then cleared.
	var/list/audit_blob

/// "interior#L4g2": slot, serial and generation. Different from real ids.
/datum/latent_entry/proc/entry_id()
	return "[slot][LEDGER_ENTRY_SEPARATOR]L[serial]g[generation]"

// ---- Eligibility and type data ----

/// A type opts out of being latent for reasons the storability sandbox can't
/// see (semantics, not side effects: containment.md §4.7) -- an admin fax
/// mid-composition, a reagent that isn't wired up. Override to return a
/// non-null reason and `latent_safe_types.dm`'s hand-kept `latent_safe`
/// still decides eligibility (dq_latent_eligible() below); this is the
/// self-documenting home for *why*, queried by the sandbox
/// (dq_storability_sandbox.dm) so an opt-out reads as a reason, not a
/// silent `FALSE`.
/atom/movable/proc/latent_unsafe_reason()
	return null

/// Whether things of `path` may be latent: latent-safe (containment.md §4.4).
DECLARE_SHARED_CACHE(latent_eligible, GLOBAL_PROC_REF(build_latent_eligible), SC_NEVER)

/proc/dq_latent_eligible(path)
	// A starts_with line can be an inline new-with-vars literal (an object, not a path): never
	// latent, and not a stable cache key.
	if(!ispath(path))
		return FALSE
	return CACHED(latent_eligible, path)

/proc/build_latent_eligible(path)
	var/atom/movable/typed = path
	return (ispath(path, /atom/movable) && initial(typed.latent_safe)) ? TRUE : FALSE

/// What one `path` adds to a holder's aggregates, from type data only: the
/// ledger snapshot shape (measures, then tag words), or null. Cached.
DECLARE_SHARED_CACHE(latent_type_snapshot, GLOBAL_PROC_REF(build_latent_type_snapshot), SC_NEVER)

/proc/dq_latent_type_snapshot(path)
	return CACHED(latent_type_snapshot, path) || null

/proc/build_latent_type_snapshot(path)
	var/list/ids = CACHED(ledger_measure_ids, "ids")
	var/count = length(ids)
	var/words = dq_ledger_tag_words()
	var/list/snapshot = new /list(count + words)
	var/any = FALSE
	for(var/i in 1 to count)
		var/value = dq_type_property(path, ids[i])
		if(!isnull(value))
			snapshot[i] = value
			any = TRUE
	var/list/tag_words = dq_property_registry().type_table(path, null)["#tags"]
	for(var/w in 1 to min(words, length(tag_words)))
		if(tag_words[w])
			snapshot[count + w] = tag_words[w]
			any = TRUE
	return any ? snapshot : null

/// A type snapshot for `n` of them: sums scale, products raise, the rest hold.
/proc/dq_latent_scale_snapshot(list/unit, n)
	if(!unit || n <= 0)
		return null
	. = unit.Copy()
	if(n == 1)
		return .
	var/count = length(CACHED(ledger_measure_ids, "ids"))
	for(var/i in 1 to count)
		var/value = unit[i]
		if(isnull(value))
			continue
		switch(dq_ledger_aggregator(i))
			if(PROP_AGG_SUM)
				.[i] = value * n
			if(PROP_AGG_PRODUCT)
				.[i] = value ** n

/// Creates one thing of an entry's type and state at `loc`.
/proc/dq_latent_create(path, list/blob, atom/loc)
	if(!blob)
		return new path(loc)
	var/list/errors = list()
	var/atom/movable/thing = state_materialize(blob, loc, STATE_FULL, errors)
	if(!thing)
		stack_trace("latent entry [path] did not materialize: [jointext(errors, "; ")]")
	return thing

/// A spawn-list value as a count (closets use numbers; list(count, variant) too).
/proc/dq_latent_spawn_count(value)
	if(isnum(value))
		return max(1, value)
	if(islist(value))
		var/list/L = value
		return (length(L) && isnum(L[1])) ? max(1, L[1]) : 1
	return 1

/// A serialized thing as an entry's state: position vars dropped (a container
/// implies them), and null when nothing is left but the type.
/proc/dq_latent_entry_blob(list/blob)
	if(!blob)
		return null
	var/list/vars = blob[STATE_KEY_VARS]
	if(vars)
		vars -= list("pixel_x", "pixel_y", "pixel_w", "pixel_z", "dir")
		if(!length(vars))
			blob -= STATE_KEY_VARS
	if(!blob[STATE_KEY_VARS] && !length(blob[STATE_KEY_CONTENTS]) && !blob[STATE_KEY_COMPONENTS])
		return null
	return blob

// ---- Generators ----

/// A holder's generator: a spawn list (type = count), or null. Override with
/// latent_generator_clear() on holders that declare contents as data.
/atom/proc/latent_generator()
	return null

/// Whether spawn-list entry `path` = `value` may be held latent (e.g. not a variant).
/atom/proc/latent_spawn_ok(path, value)
	return TRUE

/// Whether a generator line is held as an entry.
/proc/dq_latent_line_ok(atom/holder, path, value)
	return dq_latent_eligible(path) && holder.latent_spawn_ok(path, value)

/// Creates `n` of a generator line for real (variants applied).
/proc/dq_latent_spawn_real(atom/holder, path, value)
	return holder.create_latent_generator_line(path, value)

/// Forget the generator once it has been rolled.
/atom/proc/latent_generator_clear()
	return

/// At init: roll nothing, but create now the generator's types that can't be
/// latent. Holders that aren't latent create everything, as before.
/proc/dq_latent_declare(atom/holder)
	var/list/generator = holder.latent_generator()
	if(!length(generator))
		holder.latent_generator_clear()
		return
	if(!holder.latent_contents)
		create_objects_in_loc(holder, generator)
		holder.latent_generator_clear()
		return
	var/any = FALSE
	for(var/path in generator)
		if(dq_latent_line_ok(holder, path, generator[path]))
			any = TRUE
			continue
		dq_latent_spawn_real(holder, path, generator[path])
	if(any)
		holder.latent_declared = TRUE
	else
		holder.latent_generator_clear()

/// Declared -> resolved: turns the generator into entries. The ledger calls
/// this when it is built. Types that can't be latent are created real, unless
/// dq_latent_declare() already did.
/proc/dq_latent_resolve(atom/holder, datum/ledger/L)
	var/list/generator = holder.latent_generator()
	if(!length(generator))
		holder.latent_declared = FALSE
		return
	var/declared = holder.latent_declared
	holder.latent_generator_clear()
	holder.latent_declared = FALSE
	for(var/path in generator)
		if(dq_latent_line_ok(holder, path, generator[path]))
			L.latent_add(path, dq_latent_spawn_count(generator[path]))
		else if(!declared)
			dq_latent_spawn_real(holder, path, generator[path])

// ---- Ledger: entries ----

/datum/ledger
	/// Slot id -> list of /datum/latent_entry, in insertion order. Lazy.
	var/tmp/list/latent
	/// Things held as entries, over every slot.
	var/latent_total = 0
	/// The slot the next atom created straight into the holder goes to
	/// (latent_materialize()), consumed by note_enter().
	var/tmp/pending_new_slot

/// Adds `n` things of `path` (with state `blob`, or pristine) to `slot_id`,
/// merging with an identical entry. Returns the entry.
/datum/ledger/proc/latent_add(path, n = 1, list/blob = null, slot_id = null)
	var/id = slot_id || default_id
	var/datum/relation_definition/slot/def = def_by_id(id)
	if(!def || n <= 0)
		return null
	var/key = "[id]|[path]|[blob ? state_hash(blob) : ""]"
	var/list/group = latent?[id]
	for(var/datum/latent_entry/existing as anything in group)
		if(existing.key == key)
			latent_set_count(existing, existing.count + n)
			return existing
	var/datum/latent_entry/entry = new
	entry.path = path
	entry.blob = blob
	entry.slot = id
	entry.key = key
	entry.serial = ++next_serial
	entry.unit_cost = def.entry_cost(holder, path)
	LAZYINITLIST(latent)
	if(!latent[id])
		latent[id] = list()
	group = latent[id]
	group += entry
	latent_set_count(entry, n)
	return entry

/// Sets an entry's count, keeping capacity and aggregates current. At zero
/// the entry is removed.
/datum/ledger/proc/latent_set_count(datum/latent_entry/entry, n)
	// Fewer things than parked identities: the surplus things are gone for good.
	while(LAZYLEN(entry.handles) > max(0, n))
		entity_handle_release_parked(entry.handles[length(entry.handles)])
		entry.handles.len--
	remove_snapshot(entry.snapshot)
	used[entry.slot] -= entry.unit_cost * entry.count
	latent_total -= entry.count
	entry.count = max(0, n)
	entry.generation++
	if(entry.count)
		entry.snapshot = dq_latent_scale_snapshot(dq_latent_type_snapshot(entry.path), entry.count)
		add_snapshot(entry.snapshot)
		used[entry.slot] += entry.unit_cost * entry.count
		latent_total += entry.count
	else
		var/list/group = latent?[entry.slot]
		group -= entry
		if(!length(group))
			latent -= entry.slot
		UNSETEMPTY(latent)
		spent(entry)
	propagate()

/// Whether `entry` is still one of ours.
/datum/ledger/proc/latent_holds(datum/latent_entry/entry)
	if(!istype(entry) || QDELETED(entry) || !entry.count)
		return FALSE
	var/list/group = latent?[entry.slot]
	return (entry in group)

/// Entries in `slot_id` (null: every slot, in slot order), as a copy.
/datum/ledger/proc/latent_list(slot_id)
	. = list()
	if(!latent)
		return .
	if(slot_id)
		var/list/group = latent[slot_id]
		if(group)
			. += group
		return .
	for(var/datum/relation_definition/slot/def as anything in defs)
		var/list/group = latent[def.slot_id]
		if(group)
			. += group

/// Things held as entries in `slot_id` (null: every slot).
/datum/ledger/proc/latent_count(slot_id)
	if(!slot_id)
		return latent_total
	. = 0
	for(var/datum/latent_entry/entry as anything in latent?[slot_id])
		. += entry.count

/// The entry an id names, or null when stale.
/datum/ledger/proc/latent_find(entry_id)
	for(var/datum/latent_entry/entry as anything in latent_list())
		if(entry.entry_id() == entry_id)
			return entry
	return null

/// Entry -> `n` real things in the entry's slot. Returns them.
/datum/ledger/proc/latent_materialize(datum/latent_entry/entry, n = 1)
	. = list()
	if(!latent_holds(entry))
		return .
	n = min(n, entry.count)
	var/path = entry.path
	var/list/blob = entry.blob
	var/slot = entry.slot
	var/list/audit_blob = entry.audit_blob
	entry.audit_blob = null // only the first materialize after a collapse is checked
	// Identities to re-materialize into, taken before the count drops (a count drop releases
	// the entry's surplus parked handles).
	var/list/reuse = null
	for(var/i in 1 to min(n, LAZYLEN(entry.handles)))
		LAZYADD(reuse, entry.handles[length(entry.handles)])
		entry.handles.len--
	// The ledger move: the entry gives them up before they exist.
	latent_set_count(entry, entry.count - n)
	for(var/i in 1 to n)
		pending_new_slot = slot
		var/atom/movable/thing = dq_latent_create(path, blob, holder)
		pending_new_slot = null
		var/hid = LAZYLEN(reuse) ? reuse[length(reuse)] : 0
		if(hid)
			reuse.len--
		if(!thing || QDELETED(thing))
			if(hid)
				entity_handle_release_parked(hid)
			continue
		if(hid)
			entity_handle_unpark(thing, hid)
		var/list/record = entries[thing]
		if(record && record[LEDGER_E_SLOT] != slot)
			reslot(thing, slot)
		dq_latency_log("materialized", path, holder.type, holder)
		if(audit_blob)
			dq_latency_audit_check(thing, audit_blob)
			audit_blob = null // one comparison per collapse, not per n
		. += thing

/// Every entry in `slot_id` (null: all) -> real things. Returns them.
/datum/ledger/proc/latent_materialize_all(slot_id)
	. = list()
	for(var/datum/latent_entry/entry as anything in latent_list(slot_id))
		. += latent_materialize(entry, entry.count)

/// Drops every entry without creating anything (a state load replaces them).
/datum/ledger/proc/latent_clear()
	for(var/datum/latent_entry/entry as anything in latent_list())
		latent_set_count(entry, 0)

// ---- Holder API ----

/// Whether this holds latent contents, declared or resolved. Cheap: builds nothing.
/atom/proc/has_latent()
	if(!latent_contents)
		return FALSE
	if(ledger)
		return ledger.latent_total > 0
	return latent_declared || length(latent_generator()) > 0

/// Entries in `slot_id` (null: every slot). Resolves the generator.
/atom/proc/latent_entries(slot_id)
	var/datum/ledger/L = dq_ledger(src)
	return L ? L.latent_list(slot_id) : list()

/// Things held as entries in `slot_id` (null: every slot). Resolves the generator.
/atom/proc/latent_count(slot_id)
	if(!has_latent())
		return 0
	var/datum/ledger/L = dq_ledger(src)
	return L ? L.latent_count(slot_id) : 0

/// Adds `n` latent things of `path` to `slot_id`. Refuses types that can't be
/// latent and holders that don't keep entries. Returns the entry or null.
/atom/proc/latent_add(path, n = 1, list/blob = null, slot_id = null)
	if(!latent_contents || !dq_latent_eligible(path))
		return null
	var/datum/ledger/L = dq_ledger(src)
	return L?.latent_add(path, n, blob, slot_id)

/// Materializes `n` of an entry (the datum, or its id). Returns the things.
/atom/proc/latent_materialize(entry, n = 1)
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return list()
	if(istext(entry))
		entry = L.latent_find(entry)
	return L.latent_materialize(entry, n)

/// Materializes everything latent in `slot_id` (null: every slot).
/atom/proc/latent_materialize_all(slot_id)
	if(!has_latent())
		return list()
	var/datum/ledger/L = dq_ledger(src)
	return L ? L.latent_materialize_all(slot_id) : list()

/// Destroys everything latent without creating it (the holder eats its contents).
/atom/proc/latent_discard()
	if(!has_latent())
		return
	dq_ledger(src)?.latent_clear()

/// Readable summary of the latent contents, from type data: "3 jumpsuits".
/atom/proc/latent_names()
	. = list()
	for(var/datum/latent_entry/entry as anything in latent_entries())
		var/atom/typed = entry.path
		var/name = initial(typed.name)
		. += entry.count > 1 ? "[entry.count] [name]\s" : "\a [name]"

/// Collapse (containment.md §4.5): a real, simple thing inside a latent holder
/// becomes an entry again. Only when it serializes, has no contents and
/// nothing live depends on it. `held_refs` counts the caller's own references.
/// Returns TRUE if it collapsed (and src is deleted).
/atom/movable/proc/latent_collapse(held_refs = 1)
	// This proc's src is one more reference than the caller's.
	// Each proc frame on src holds two references (measured): see latent_collapse_refusal().
	var/refusal = latent_collapse_refusal(held_refs + 2)
	if(refusal)
		GLOB.latent_last_refusal = refusal
		return FALSE
	var/datum/ledger/L = loc.ledger
	var/list/record = L.entries[src]
	var/list/errors = list()
	var/list/blob = state_serialize(src, STATE_FULL, errors)
	if(!blob)
		GLOB.latent_last_refusal = jointext(errors, "; ")
		return FALSE
	// dq_latent_entry_blob() mutates and returns its argument, so `blob` is
	// the entry blob from here on -- audit_blob below is that same object,
	// captured before merging (an identical existing entry would otherwise
	// share it with a different collapse's copy).
	blob = dq_latent_entry_blob(blob)
	var/slot = record[LEDGER_E_SLOT]
	var/path = type
	var/holder_type = loc.type
	// Keep the identity (ownership.md sec 4.1): the handle slot is parked and relation views naming
	// this thing go dormant, to re-link when the entry re-materializes into the same slot.
	var/hid = entity_handle_park(src)
	replaced_by(src)
	var/datum/latent_entry/entry = L.latent_add(path, 1, blob, slot)
	if(hid)
		if(entry)
			LAZYADD(entry.handles, hid)
		else
			entity_handle_release_parked(hid)
	if(entry && dq_latency_audit_enabled())
		entry.audit_blob = blob
	dq_latency_log("collapsed", path, holder_type)
	return TRUE

/// Why this can't collapse into an entry now, or null. `held_refs` counts
/// the caller's own references to src.
/atom/movable/proc/latent_collapse_refusal(held_refs = 1)
	var/atom/holder = loc
	if(QDELETED(src))
		return "it is gone"
	if(!holder?.latent_contents)
		return "its holder keeps no latent contents"
	if(!latent_safe)
		return "[type] is not latent-safe"
	if(length(contents))
		return "it holds things"
	var/datum/ledger/L = dq_ledger(holder)
	if(!L?.entries[src])
		return "it is not in a slot"
	// This proc frame holds two more references than the caller's (measured on
	// BYOND 516; the reference finder sees nothing else, and dq_latent_collapse
	// checks that one real outside reference still blocks).
	var/list/blockers = state_collapse_blockers(held_refs + 2)
	if(length(blockers))
		return jointext(blockers, "; ")
	return null

// ---- Slot definitions ----

/// What one thing of `path` costs in this slot, from type data.
/datum/relation_definition/slot/proc/entry_cost(atom/holder, path)
	switch(capacity_model)
		if(SLOT_CAPACITY_NONE)
			return 0
		if(SLOT_CAPACITY_COUNT)
			return 1
		if(SLOT_CAPACITY_SIZE)
			return dq_type_property(path, PROP_SIZE_CLASS) || 0
		if(SLOT_CAPACITY_MASS)
			return dq_type_property(path, PROP_MASS) || 0
	return 1

// ---- Damage (damage.md §6, §7) ----

/// An explosion reaches the contents at `severity`: entries are resolved as
/// data. Each thing is tried on a sandboxed probe; destroyed ones are removed,
/// survivors keep their new state. Nothing is created in the world.
/atom/proc/latent_blast(severity)
	if(!has_latent())
		return
	var/datum/ledger/L = dq_ledger(src)
	if(!L)
		return
	for(var/datum/latent_entry/entry as anything in L.latent_list())
		var/path = entry.path
		var/list/blob = entry.blob
		var/slot = entry.slot
		var/list/survivors = list() // state hash -> list(blob, count)
		for(var/i in 1 to entry.count)
			var/list/outcome = dq_latent_probe_blast(path, blob, severity)
			if(!outcome)
				continue
			var/list/after = outcome[1]
			var/hash = after ? state_hash(after) : ""
			if(!survivors[hash])
				survivors[hash] = list(after, 0)
			var/list/tally = survivors[hash]
			tally[2]++
		L.latent_set_count(entry, 0)
		for(var/hash in survivors)
			var/list/tally = survivors[hash]
			L.latent_add(path, tally[2], tally[1], slot)

/// One thing of `path` (state `blob`) takes a blast in the sandbox. Returns
/// null if it was destroyed, else list(its new blob, or null if pristine).
/proc/dq_latent_probe_blast(path, list/blob, severity)
	var/atom/movable/probe = state_new_unmaterialized(path, null)
	if(blob)
		state_apply(probe, blob, STATE_FULL)
	probe.containment_blast_exposure(severity)
	if(QDELETED(probe))
		return null
	var/list/after = dq_latent_entry_blob(state_serialize(probe, STATE_FULL))
	spent(probe)
	return list(after)
