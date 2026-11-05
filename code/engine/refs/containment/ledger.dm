// The containment ledger (doc/rewrite/containment.md §2).
//
// Every holder that declares slots (slot_def.dm) gets one /datum/ledger, made
// on first use by dq_ledger(). It records which slot each thing inside is in,
// gives each an entry id, and answers the holder's aggregates (mass, heat
// capacity, minimum thresholds, capability tags) when asked: they are folded
// from the things inside on a read (recompute()), not kept current on every
// insert and remove. The only readers are contents_property() and
// contents_has_tag(), and they are rare; a move runs on every body, organ and
// item, so it pays only for its bookkeeping.
//
// Bookkeeping happens at the one place a movable's loc changes: doMove()
// calls note_exit() on the old holder's ledger and note_enter() on the new
// one, right after the loc write and before Exited()/Entered(). So every
// forceMove is accounted for, transactional or not. The transaction API
// (api.dm) adds the checks in front and picks the slot.
//
// Things that arrive without a move (new(holder) during Initialize) are
// adopted by sync(), which every read and transaction runs first. It costs one
// length() comparison when nothing is missing. Raw `loc =` and `contents +=`
// writes skip all of this, which is why tools/ci/containment_lint.py forbids
// them outside its allowlist.

// The containment engine's own per-atom ledger; made and torn down by ledger.dm / the destroy transaction
/datum/rx_state
	var/datum/ledger/containment_ledger

CAPABILITIES(/datum/rx_state)
	ref_one(nameof(claimed_by), /datum/pending_op) // the waiting claiming op that holds this entity; it clears when the op is deleted
	owns_one(nameof(containment_ledger), /datum/ledger)
	owns_one(nameof(lookup_scope), /datum/lookup_read_scope)

/atom/proc/containment_ledger()
	RETURN_TYPE(/datum/ledger)
	return rx?.containment_ledger

/atom/proc/set_containment_ledger(datum/ledger/value)
	if(!value && !rx)
		return
	var/datum/rx_state/S = rx_of(src)
	return rel_set(S, nameof(S.containment_ledger), value)

/atom/proc/clear_containment_ledger()
	if(rx)
		return rel_clear(rx, nameof(rx.containment_ledger))

/// The ledger for `holder`, made on first use, synced. Null if it has no slots.
/// `destroying`: the destroy transaction's contents phase, which runs after
/// phase 0 has marked the holder QDELETED and must still resolve a holder whose
/// latent contents were never built (an unmaterialized probe, a sealed kit).
/proc/dq_ledger(atom/holder, destroying = FALSE)
	READS_FROM(holder) // the ledger reflects this holder's containment state
	RETURN_TYPE(/datum/ledger)
	if(!holder)
		return null
	var/datum/ledger/L = holder.containment_ledger()
	if(L && length(holder.contents) == L.tracked)
		return L
	// Building the ledger and adopting contents that arrived without a move are the ledger's own bookkeeping, done once and the same whoever asks: a
	// condition or an output that reads the contents of a holder it is the first to ask about is not writing the holder's state, so the purity
	// guard (code/engine/parts/purity.dm) is lifted for it.
	var/pure_depth = GLOB.op_pure_depth
	var/derived_depth = GLOB.derived_evaluating
	var/adopting = GLOB.ledger_adopting
	GLOB.op_pure_depth = 0
	GLOB.derived_evaluating = 0
	GLOB.ledger_adopting = TRUE
	L = dq_ledger_open(holder, destroying)
	GLOB.op_pure_depth = pure_depth
	GLOB.derived_evaluating = derived_depth
	GLOB.ledger_adopting = adopting
	return L

/// TRUE while a ledger is being built or is adopting contents (dq_ledger()): the holder marks itself changed by the links it makes, and a refresh that
/// asked is not writing state when that happens.
GLOBAL_VAR_INIT(ledger_adopting, FALSE)

/// dq_ledger()'s slow path: the ledger built if there is none, and synced.
/proc/dq_ledger_open(atom/holder, destroying = FALSE)
	RETURN_TYPE(/datum/ledger)
	var/datum/ledger/L = holder.containment_ledger()
	if(!L)
		var/list/defs = dq_slot_defs_for(holder)
		if(!defs || (QDELETED(holder) && !(destroying && holder.gc_destroyed == GC_CURRENTLY_BEING_QDELETED)))
			return null
		L = new /datum/ledger(holder, defs)
		holder.set_containment_ledger(L)
		// Building the ledger is the first exact question: resolve the generator (C5).
		if(holder.latent_contents_enabled())
			dq_latent_resolve(holder, L)
			// Candidate for the latency sweep (roadmap C10, containment.md §4.7).
			holder.register_latency_sweep()
	L.sync()
	return L

/// The ledger a thing that just moved into `holder` is entered in: made now when `holder` declares slots and has none yet, so a plain
/// forceMove into a net or a jar registers in the default slot like move_into() does. Null for a holder without slots (turfs skip the
/// lookup: they are the hot destination of nearly every move).
/proc/dq_ledger_for_arrival(atom/holder)
	RETURN_TYPE(/datum/ledger)
	if(isturf(holder) || !dq_slot_defs_for(holder))
		return null
	return dq_ledger(holder)

/// The existing ledger for `holder`, synced, or null. Unlike dq_ledger(), never
/// creates one -- for read paths (rolling up a nested holder's contribution,
/// walking a holder's children) that must not be what makes an empty holder
/// start owning a ledger of its own.
/proc/dq_ledger_peek(atom/holder)
	RETURN_TYPE(/datum/ledger)
	var/datum/ledger/L = holder?.containment_ledger()
	L?.sync()
	return L

/// The measures the ledger aggregates: every registered measure with an
/// aggregator, in a fixed order. Tag words follow them in a snapshot.
/// Read with CACHED(ledger_measure_ids, "ids"); built once on first use.
DECLARE_SHARED_CACHE(ledger_measure_ids, GLOBAL_PROC_REF(dq_build_ledger_measure_ids), SC_NEVER)

/proc/dq_build_ledger_measure_ids()
	RETURN_TYPE(/list)
	var/list/ids = list()
	var/datum/property_registry/registry = dq_property_registry()
	for(var/id in registry.measure_ids)
		var/datum/property_def/def = registry.defs[id]
		if(def.aggregator != PROP_AGG_NONE)
			ids += id
	return ids

/// Number of tag words in a snapshot.
/proc/dq_ledger_tag_words()
	var/static/words
	if(isnull(words))
		words = max(1, CEILING(length(dq_property_registry().tag_bits) / PROP_TAG_WORD_BITS, 1))
	return words

/// Aggregator for position `i` of a snapshot.
/proc/dq_ledger_aggregator(i)
	var/list/ids = CACHED(ledger_measure_ids, "ids")
	if(i > length(ids))
		return PROP_AGG_OR
	var/datum/property_def/def = dq_property_registry().defs[ids[i]]
	return def.aggregator

/// What `thing` adds to its holder's aggregates: its own property values
/// combined with its own ledger's aggregates (so nested holders roll up).
/// A list of measure values then tag words, or null when it adds nothing.
/// A nested holder's contribution is folded from its own contents.
/proc/dq_ledger_contribution(atom/movable/thing)
	var/datum/property_registry/registry = dq_property_registry()
	var/list/ids = CACHED(ledger_measure_ids, "ids")
	var/count = length(ids)
	var/words = dq_ledger_tag_words()
	var/list/nested
	var/datum/ledger/inner = dq_ledger_peek(thing)
	if(inner)
		nested = inner.recompute()
	var/list/snapshot = new /list(count + words)
	var/any = FALSE
	for(var/i in 1 to count)
		var/value = dq_property(thing, ids[i])
		if(nested)
			value = dq_property_combine(dq_ledger_aggregator(i), value, nested[i])
		if(!isnull(value))
			snapshot[i] = value
			any = TRUE
	for(var/tag in registry.tag_bits)
		if(!dq_has_tag(thing, tag))
			continue
		var/bit = registry.tag_bits[tag]
		var/word = count + round(bit / PROP_TAG_WORD_BITS) + 1
		snapshot[word] = (snapshot[word] || 0) | (1 << (bit % PROP_TAG_WORD_BITS))
		any = TRUE
	if(nested)
		for(var/w in count + 1 to count + words)
			if(nested[w])
				snapshot[w] = (snapshot[w] || 0) | nested[w]
				any = TRUE
	return any ? snapshot : null

/datum/ledger
	/// The holder's slot (holder() reads it back): the ledger keeps no reference to its holder.
	var/tmp/holder_slot = 0
	/// The holder type's /datum/relation_definition/slot singletons, in declaration order.
	var/tmp/list/defs
	/// Id of the slot legacy moves land in.
	var/default_id
	/// Slot id -> list of things, in insertion order.
	var/tmp/list/slots
	/// Slot id -> capacity used.
	var/list/used
	/// Thing's slot -> entry record (LEDGER_E_*): the ledger keeps no reference to a thing (slot_datums() reads them back).
	var/tmp/alist/entries
	/// Things recorded, for sync()'s fast path.
	var/tracked = 0
	/// Entry serials only increase (the last one issued), so an entry id is never reused.
	var/last_serial = 0
	/// The slot the next note_enter() of the thing whose slot is `pending_thing_slot` goes to (api.dm).
	var/tmp/pending_thing_slot = 0
	var/pending_slot
	/// Keyed slots only (J4): slot id -> (key -> thing). Lazy; a holder with
	/// no keyed slot never allocates this.
	var/tmp/list/keys
	/// L1: the flags (LEDGER_MOVE_* ) the next note_enter() consumes, set by
	/// the mover just before the forceMove/reslot that triggers it. Same
	/// pattern as pending_thing_slot/pending_slot.
	var/tmp/pending_flags
	/// L1: the flags the next note_exit() on *this* (the departing) ledger
	/// consumes. Set by the mover on the thing's current ledger just before
	/// the move that triggers it.
	var/tmp/pending_exit_flags
	/// J5: how many of our current slot members have their own nonzero
	/// move_hooks (own bits or a subtree beneath them). Keeps this holder's
	/// MOVE_HOOK_SUBTREE bit accurate in O(1); see adjust_hooked().
	var/tmp/hooked_count = 0

/// The holder, or null once it is deleted.
/datum/ledger/proc/holder()
	return slot_datum(holder_slot)

/datum/ledger/New(atom/holder, list/defs)
	..()
	holder_slot = SLOT(holder)
	src.defs = defs
	slots = list()
	used = list()
	entries = alist()
	for(var/datum/relation_definition/slot/def as anything in defs)
		slots[def.slot_id] = list()
		used[def.slot_id] = 0
		if(def.is_default && !default_id)
			default_id = def.slot_id
	if(!default_id)
		var/datum/relation_definition/slot/first = defs[1]
		default_id = first.slot_id

// the ledger is the containment engine itself; it lets go of its holder.

/datum/ledger/lifecycle_dematerialize()
	..()
	if(holder())
		holder().unregister_latency_sweep() // the sweep list holds a hard ref

/datum/ledger/proc/def_by_id(id)
	RETURN_TYPE(/datum/relation_definition/slot)
	for(var/datum/relation_definition/slot/def as anything in defs)
		if(def.slot_id == id)
			return def
	return null

// ---- Keyed slots (J4) ----

/datum/ledger/proc/index_key(slot_id, key, atom/movable/thing)
	LAZYINITLIST(keys)
	var/list/slot_keys = keys[slot_id]
	if(!slot_keys)
		slot_keys = list()
		keys[slot_id] = slot_keys
	slot_keys[key] = thing

/datum/ledger/proc/unindex_key(slot_id, key, atom/movable/thing)
	if(isnull(key) || !keys)
		return
	var/list/slot_keys = keys[slot_id]
	if(!slot_keys)
		return
	if(slot_keys[key] == thing)
		slot_keys -= key
		if(!length(slot_keys))
			keys -= slot_id
	UNSETEMPTY(keys)

/// The thing keyed `key` in `slot_id`, or null. O(1).
/datum/ledger/proc/slot_lookup(slot_id, key)
	if(isnull(key) || !keys)
		return null
	var/list/slot_keys = keys[slot_id]
	return slot_keys ? slot_keys[key] : null

/// Re-reads `thing`'s key in whichever of our slots it is in, and re-indexes
/// it. Called when something that changes `slot_key()`'s answer happens to a
/// thing already inserted (its holder doesn't know on its own).
/datum/ledger/proc/rekey(atom/movable/thing)
	var/list/entry = entries[slot_known(thing)]
	if(!entry)
		return
	var/id = entry[LEDGER_E_SLOT]
	var/datum/relation_definition/slot/def = def_by_id(id)
	if(!def?.keyed)
		return
	unindex_key(id, entry[LEDGER_E_KEY], thing)
	var/key = thing.slot_key()
	entry[LEDGER_E_KEY] = key
	if(!isnull(key))
		index_key(id, key, thing)

// ---- Sync ----

/// Adopts contents that arrived without a move and forgets things that left
/// without one. One comparison when nothing changed.
/// The things the ledger has entries for, as a new list.
/datum/ledger/proc/entry_things()
	. = list()
	for(var/entry_slot in entries)
		var/atom/movable/thing = slot_datum(entry_slot)
		if(thing)
			. += thing

/datum/ledger/proc/sync()
	if(length(holder().contents) == tracked)
		return
	for(var/atom/movable/thing as anything in entry_things())
		if(thing.loc != holder())
			note_exit(thing)
	for(var/atom/movable/thing as anything in holder().contents)
		// A thing being deleted left its slot in destroy phase 4 (it keeps its loc until phase 7):
		// note_enter()'s teardown guard never re-adopts it.
		if(!entries[slot_known(thing)])
			note_enter(thing)

// ---- Bookkeeping (called from doMove) ----

/// TRUE when it recorded `thing`.
/datum/ledger/proc/note_enter(atom/movable/thing)
	if(entries[slot_known(thing)])
		return FALSE
	var/id = default_id
	if(pending_thing_slot && pending_thing_slot == SLOT_KNOWN(thing))
		id = pending_slot
		pending_thing_slot = 0
		pending_slot = null
	else if(pending_new_slot)
		id = pending_new_slot
		pending_new_slot = null
	var/flags = pending_flags
	pending_flags = null
	if(!own_guard(holder(), thing, "contents adoption", LIFECYCLE_PHASE_LINKS)) // the one teardown guard (guard.dm)
		return FALSE
	var/datum/relation_definition/slot/def = def_by_id(id)
	var/cost = def.cost(holder(), thing)
	var/key = def.keyed ? thing.slot_key() : null
	entries[SLOT(thing)] = list(id, ++last_serial, cost, key)
	if(def.keyed && !isnull(key))
		index_key(id, key, thing)
	var/list/things = slots[id]
	things += thing
	used[id] += cost
	tracked++
	. = TRUE
	if(thing.containment_move_flags())
		adjust_hooked(1)
	// The one idle-tracking seam (roadmap C10, containment.md §4.7): this is
	// the ledger's own move path, which also covers adoption (sync()) and
	// materialization, so nothing else needs its own touch call. Moves onto
	// DQ Medical's joint before/after-move transaction hook in one place
	// once that lands (medical_frameworks.md).
	dq_latent_touch(thing)
	PUBLISH_CHANGE(holder(), SLOT_OCCUPANCY_KEY)
	holder().on_slot_changed(id, thing, TRUE)
	PUBLISH(holder(), slot_inserted, thing = thing, slot_id = id)
	entity_slot_entered(holder(), thing, def)
	activations_slot_enter(thing, holder(), id)
	if(thing.slot_hooks_enabled())
		thing.on_slotted(holder(), id, flags)

/// TRUE when it forgot `thing`.
/datum/ledger/proc/note_exit(atom/movable/thing)
	var/list/entry = entries[slot_known(thing)]
	if(!entry)
		return FALSE
	var/flags = pending_exit_flags
	pending_exit_flags = null
	var/id = entry[LEDGER_E_SLOT]
	var/datum/relation_definition/slot/def = def_by_id(id)
	if(def?.keyed)
		unindex_key(id, entry[LEDGER_E_KEY], thing)
	entries -= slot_known(thing)
	var/list/things = slots[id]
	things -= thing
	used[id] -= entry[LEDGER_E_COST]
	tracked--
	. = TRUE
	if(thing.containment_move_flags())
		adjust_hooked(-1)
	PUBLISH_CHANGE(holder(), SLOT_OCCUPANCY_KEY)
	holder().on_slot_changed(id, thing, FALSE)
	PUBLISH(holder(), slot_removed, thing = thing, slot_id = id)
	entity_slot_left(holder(), thing, def)
	activations_slot_exit(thing, holder(), id)
	if(thing.slot_hooks_enabled())
		thing.on_unslotted(holder(), id, flags)
	// The slot was its ownership (doc/rewrite/ownership.md sec 1.1): a CONTAINED / SPILL owned var
	// naming it lets it go.
	if(thing.own_holder_ref && !QDELETED(holder()))
		own_contents_exit(holder(), thing)

/// Moves a thing already inside between two of the holder's slots.
/datum/ledger/proc/reslot(atom/movable/thing, new_id, flags = 0)
	var/list/entry = entries[slot_known(thing)]
	var/old_id = entry[LEDGER_E_SLOT]
	if(old_id == new_id)
		return
	var/list/old_things = slots[old_id]
	old_things -= thing
	used[old_id] -= entry[LEDGER_E_COST]
	var/datum/relation_definition/slot/old_def = def_by_id(old_id)
	if(old_def?.keyed)
		unindex_key(old_id, entry[LEDGER_E_KEY], thing)
	holder().on_slot_changed(old_id, thing, FALSE)
	PUBLISH(holder(), slot_removed, thing = thing, slot_id = old_id)
	entity_slot_left(holder(), thing, old_def)
	activations_slot_exit(thing, holder(), old_id)
	if(thing.slot_hooks_enabled())
		thing.on_unslotted(holder(), old_id, flags)
	var/datum/relation_definition/slot/def = def_by_id(new_id)
	entry[LEDGER_E_SLOT] = new_id
	entry[LEDGER_E_SERIAL] = ++last_serial
	entry[LEDGER_E_COST] = def.cost(holder(), thing)
	var/key = def.keyed ? thing.slot_key() : null
	entry[LEDGER_E_KEY] = key
	if(def.keyed && !isnull(key))
		index_key(new_id, key, thing)
	var/list/new_things = slots[new_id]
	new_things += thing
	used[new_id] += entry[LEDGER_E_COST]
	PUBLISH_CHANGE(holder(), SLOT_OCCUPANCY_KEY)
	holder().on_slot_changed(new_id, thing, TRUE)
	PUBLISH(holder(), slot_inserted, thing = thing, slot_id = new_id)
	entity_slot_entered(holder(), thing, def)
	activations_slot_enter(thing, holder(), new_id)
	if(thing.slot_hooks_enabled())
		thing.on_slotted(holder(), new_id, flags)

// ---- Aggregates ----

/// The aggregates folded from what is inside now, as a snapshot-shaped list, recursing into nested holders. Reads each thing's
/// properties as they are at this moment, so there is nothing to refresh when one of them changes.
/datum/ledger/proc/recompute()
	sync()
	. = new /list(length(CACHED(ledger_measure_ids, "ids")) + dq_ledger_tag_words())
	for(var/atom/movable/thing as anything in holder().contents)
		var/list/snapshot = dq_ledger_contribution(thing)
		if(!snapshot)
			continue
		for(var/i in 1 to length(snapshot))
			.[i] = dq_property_combine(dq_ledger_aggregator(i), .[i], snapshot[i])
	for(var/datum/latent_entry/entry as anything in latent_list())
		var/list/snapshot = entry.snapshot
		for(var/i in 1 to length(snapshot))
			.[i] = dq_property_combine(dq_ledger_aggregator(i), .[i], snapshot[i])

/// Aggregate of measure `id` over everything inside, or null.
/datum/ledger/proc/aggregate(id)
	var/list/ids = CACHED(ledger_measure_ids, "ids")
	var/index = ids.Find(id)
	if(!index)
		CRASH("[id] is not a ledger aggregate")
	var/list/totals = recompute()
	return totals[index]

/// Whether anything inside has tag `tag`.
/datum/ledger/proc/has_tag(tag)
	var/bit = dq_property_registry().tag_bits[tag]
	if(isnull(bit))
		CRASH("unknown tag [tag]")
	var/list/totals = recompute()
	return (totals[length(CACHED(ledger_measure_ids, "ids")) + round(bit / PROP_TAG_WORD_BITS) + 1] & (1 << (bit % PROP_TAG_WORD_BITS))) ? TRUE : FALSE

/// Mismatches between the ledger and the holder's real contents, as text. Empty when sound.
/datum/ledger/proc/verify()
	. = list()
	var/total = 0
	for(var/id in slots)
		var/list/things = slots[id]
		total += length(things)
		var/sum = 0
		for(var/atom/movable/thing as anything in things)
			if(thing.loc != holder())
				. += "[holder()] slot [id] lists [thing], which is in [thing.loc]"
			var/list/entry = entries[slot_known(thing)]
			sum += entry ? entry[LEDGER_E_COST] : 0
		for(var/datum/latent_entry/latent_entry as anything in latent?[id])
			sum += latent_entry.unit_cost * latent_entry.count
			if(latent_entry.count <= 0)
				. += "[holder()] slot [id] keeps an empty latent entry [latent_entry.path]"
		if(abs(sum - used[id]) > 1e-4)
			. += "[holder()] slot [id] used [used[id]], entries sum to [sum]"
	if(total != tracked || total != length(entries))
		. += "[holder()] tracks [tracked], slots list [total], entries [length(entries)]"
	if(total != length(holder().contents))
		. += "[holder()] holds [length(holder().contents)] but the ledger lists [total]"
	. += verify_keys()

/// Recomputes the key index from the entries and compares it to `keys`.
/datum/ledger/proc/verify_keys()
	. = list()
	var/list/want = list()
	for(var/atom/movable/thing as anything in entry_things())
		var/list/entry = entries[slot_known(thing)]
		var/id = entry[LEDGER_E_SLOT]
		var/datum/relation_definition/slot/def = def_by_id(id)
		if(!def?.keyed)
			continue
		var/key = entry[LEDGER_E_KEY]
		if(isnull(key))
			continue
		LAZYINITLIST(want)
		var/list/slot_keys = want[id]
		if(!slot_keys)
			slot_keys = list()
			want[id] = slot_keys
		if(slot_keys[key])
			. += "[holder()] slot [id] key [key] is used by more than one thing"
			continue
		slot_keys[key] = thing
	for(var/id in want)
		var/list/slot_keys = want[id]
		var/list/have_keys = keys?[id]
		for(var/key in slot_keys)
			if(have_keys?[key] != slot_keys[key])
				. += "[holder()] slot [id] key [key] should index [slot_keys[key]], indexes [have_keys?[key]]"
	for(var/id in keys)
		var/list/have_keys = keys[id]
		var/list/slot_keys = want[id]
		for(var/key in have_keys)
			if(!slot_keys || !slot_keys[key])
				. += "[holder()] slot [id] indexes stale key [key] -> [have_keys[key]]"

// ---- Entry ids ----

/// "interior#12": the slot and a serial unique for this holder's lifetime.
/datum/ledger/proc/entry_id(atom/movable/thing)
	var/list/entry = entries[slot_known(thing)]
	return entry ? "[entry[LEDGER_E_SLOT]][LEDGER_ENTRY_SEPARATOR][entry[LEDGER_E_SERIAL]]" : null

/// The thing an entry id names, or null when stale (it left, or was reslotted).
/datum/ledger/proc/find_entry(entry_id)
	var/split = findlasttext(entry_id, LEDGER_ENTRY_SEPARATOR)
	if(!split)
		return null
	var/id = copytext(entry_id, 1, split)
	var/serial = text2num(copytext(entry_id, split + length(LEDGER_ENTRY_SEPARATOR)))
	for(var/atom/movable/thing as anything in slots[id])
		var/list/entry = entries[slot_known(thing)]
		if(entry[LEDGER_E_SERIAL] == serial)
			return thing
	return null

/// Every thing inside, slots in declaration order, each in insertion order.
/// The state serializer numbers children in this order (code/datums/state/).
/datum/ledger/proc/ordered()
	. = list()
	for(var/datum/relation_definition/slot/def as anything in defs)
		. += slots[def.slot_id]

/// Called on the holder whenever a thing enters or leaves one of its slots.
/// Runs inside the move, so it must not sleep. An occupant pod's slot tells its pod (occupant_pod_slot_changed(): one list read for any other slot).
/atom/proc/on_slot_changed(slot_id, atom/movable/thing, inserted)
	containment_slot_changed(slot_id, thing, inserted)

// ---- Thing-side commit hooks (J6) ----

/// Set on a type that overrides on_slotted()/on_unslotted(), so a plain
/// thing that never will skips the proc call on every insert and remove.

/// Called on `thing` right after it commits into `slot_id` on `holder`:
/// from note_enter() and from reslot() (a move between two of the same
/// holder's slots). Runs inside the move, so it must not sleep, move or
/// qdel anything. Only called when `has_slot_hooks` is set. `flags` carries
/// LEDGER_MOVE_FORCED and, during the destroy transaction's contents phase
/// (L1 §3), LEDGER_MOVE_DESTROYING -- skip re-derivation work when it's set.
/atom/movable/proc/on_slotted(atom/holder, slot_id, flags = 0)
	return

/// Called on `thing` right after it leaves `slot_id` on `holder`: from
/// note_exit() and from reslot(). Same constraints and `flags` as on_slotted().
/atom/movable/proc/on_unslotted(atom/holder, slot_id, flags = 0)
	return

// ---- Keyed slots (J4) ----

/// The key a keyed slot stores for `thing` at insert, or null. Override per
/// type (a body part returns its organ_tag).
/atom/movable/proc/slot_key()
	return null

/// Re-reads and re-indexes `thing`'s key in whichever of its holder's slots
/// it is in. Call this after something changes what slot_key() answers for
/// a thing that is already inserted into a keyed slot.
/atom/movable/proc/ledger_rekey()
	var/datum/ledger/L = dq_ledger_peek(loc)
	L?.rekey(src)

// ---- Dynamic tags (J7) ----

// ---- J5: the move hook gate ----

/// MOVE_HOOK_CLOCK, MOVE_HOOK_LATENCY and/or MOVE_HOOK_SUBTREE (the last
/// maintained by the ledger, not set by hand). doMove() gates on this with
/// one var test; see code/defines/engine/containment.dm's file header.

/// Called on `src` right before `loc =` (doMove()), if MOVE_HOOK_CLOCK or
/// MOVE_HOOK_LATENCY is set. Must not move, qdel or sleep -- a debug assert
/// in doMove() checks `loc` didn't change out from under it. May call
/// after()/qdel(watch) and clock procs.
/atom/movable/proc/move_hook_before()
	return

/// Called on `src` right after note_enter() (doMove()), before
/// Exited()/Uncrossed(), if MOVE_HOOK_CLOCK or MOVE_HOOK_LATENCY is set. Not
/// called on a move into nullspace (deletion) -- there is no "after" state
/// to hook into; move_hook_before() already ran, so clocks settle and cancel
/// there instead. Same constraints as move_hook_before().
/atom/movable/proc/move_hook_after()
	return

/// Walks `src`'s own contents for hooked descendants and fires their
/// before/after hooks too, pruning any branch whose move_hooks is 0
/// (nothing hooked anywhere inside it). This is what lets a clocked item
/// deep in a carried bag react to the bag moving, even though the item's
/// own `loc` never changes.
/atom/movable/proc/move_hook_walk(before)
	for(var/atom/movable/child as anything in contents)
		if(!child.containment_move_flags())
			continue
		if(child.containment_move_flags() & (MOVE_HOOK_CLOCK | MOVE_HOOK_LATENCY))
			if(before)
				child.move_hook_before()
			else
				child.move_hook_after()
		if(child.containment_move_flags() & MOVE_HOOK_SUBTREE)
			child.move_hook_walk(before)

/// Dispatches both the own-hook call and the subtree walk for one side of a
/// move. doMove() calls this only when `move_hooks` is already known
/// nonzero (its one var test), so this itself never runs for an unhooked
/// mover -- the whole point of the gate.
/atom/movable/proc/move_hooks_dispatch(before)
#ifdef TESTING
	var/atom/check_loc = loc
#endif
	if(containment_move_flags() & (MOVE_HOOK_CLOCK | MOVE_HOOK_LATENCY))
		if(before)
			move_hook_before()
		else
			move_hook_after()
	if(containment_move_flags() & MOVE_HOOK_SUBTREE)
		move_hook_walk(before)
#ifdef TESTING
	if(loc != check_loc)
		stack_trace("[type] move_hook_before()/move_hook_after()/move_hook_walk() moved [src] -- move hooks must not move, qdel or sleep")
#endif

/// Keeps this ledger's holder's own MOVE_HOOK_SUBTREE bit accurate as
/// `thing` (which has just entered or is about to leave) enters or leaves,
/// and bubbles a flip up to the parent ledger -- the same shape as
/// propagate() bubbling aggregate changes, but for hookedness, which isn't
/// part of the property snapshot. O(1): a counter and a bit test, no scan,
/// no P1 query.
/datum/ledger/proc/adjust_hooked(delta)
	var/had = hooked_count > 0
	hooked_count += delta
	var/have = hooked_count > 0
	if(had == have)
		return
	// move_hooks (and the whole move-hook walk, J5) only exists on
	// /atom/movable -- a turf holder (declared slots but never itself
	// moves) has nothing to set, but its hooked_count still needs to be
	// right in case something ever asks.
	if(ismovable(holder()))
		var/atom/movable/AM = holder()
		if(have)
			AM.set_containment_move_flags(AM.containment_move_flags() | MOVE_HOOK_SUBTREE)
		else
			AM.set_containment_move_flags(AM.containment_move_flags() & ~MOVE_HOOK_SUBTREE)
	var/datum/ledger/parent_ledger = dq_ledger_peek(holder().loc)
	parent_ledger?.adjust_hooked(have ? 1 : -1)

/// References this ledger holds to `thing` (for the collapse refcount check).
/datum/ledger/proc/refs_to(atom/movable/thing)
	. = 0
	var/list/entry = entries[slot_known(thing)]
	if(entry)
		. += 1 // the entries key
		var/list/things = slots[entry[LEDGER_E_SLOT]]
		if(thing in things)
			. += 1
	if(pending_thing_slot && pending_thing_slot == SLOT_KNOWN(thing))
		. += 1
