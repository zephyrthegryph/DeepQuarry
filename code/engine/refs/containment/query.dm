// Engine slot metadata hook: COUNT/NONE/default unit cost is immutable.
// SIZE/MASS require their real property-provider subscription contract before
// those slot kinds opt in; they must not silently advertise an empty readset.
/datum/relation_definition/slot/proc/cost_read_keys(atom/holder, atom/movable/thing)
	if(capacity_model == SLOT_CAPACITY_SIZE || capacity_model == SLOT_CAPACITY_MASS)
		CRASH("property capacity needs a native property read provider")
	return list()

// Engine pure query: retain insertion-time accounting, adjusting only the
// temporary answer for residents whose current cost changed before a drain.
// Cached cost, used, aggregate snapshots and custody remain untouched.
/datum/ledger/proc/current_used(slot_id)
	var/total = used[slot_id]
	var/datum/relation_definition/slot/def = def_by_id(slot_id)
	if(!def)
		return total
	var/list/residents = slots[slot_id]
	for(var/atom/movable/thing as anything in residents)
		var/list/entry = entries[thing]
		if(entry && entry[LEDGER_E_SLOT] == slot_id)
			total += def.cost(holder, thing) - entry[LEDGER_E_COST]
	return total


// Engine declarations: add beside the existing slot query methods.
/datum/relation_definition/slot/proc/admission_read_keys(atom/holder, atom/movable/thing, mob/actor)
	return list()

/datum/relation_definition/slot/proc/removal_read_keys(atom/holder, atom/movable/thing, mob/actor)
	return list()

// Engine structural collector: records both source and destination even when
// the first refusal currently hides a later requirement. No effects are run.
/proc/dq_ledger_read_keys(atom/movable/thing, atom/holder, slot_id, mob/actor, check_removal = TRUE)
	. = list()
	if(!thing || QDELETED(thing) || !holder || QDELETED(holder))
		return
	. += list(list(thing, ATOM_KEY_LOC))
	for(var/atom/A = holder; A; A = A.loc)
		. += list(list(A, ATOM_KEY_LOC))
	. += list(list(holder, SLOT_OCCUPANCY_KEY))
	var/datum/ledger/dest = dq_ledger(holder)
	var/id = isnull(slot_id) ? dest?.default_id : slot_id
	var/datum/relation_definition/slot/def = dest?.def_by_id(id)
	if(def)
		. += def.admission_read_keys(holder, thing, actor)
		if(def.capacity_model != SLOT_CAPACITY_NONE && def.capacity_for(holder) != INFINITY)
			. += def.cost_read_keys(holder, thing)
			for(var/atom/movable/resident as anything in dest.slots[id])
				. += def.cost_read_keys(holder, resident)
		. += op_transfer_read_keys(holder, /datum/act/insert, thing, id, actor)
	if(check_removal)
		. += dq_ledger_removal_read_keys(thing, actor)

/proc/dq_ledger_removal_read_keys(atom/movable/thing, mob/actor)
	. = list()
	if(!thing || QDELETED(thing))
		return
	. += list(list(thing, ATOM_KEY_LOC))
	var/atom/source = thing.loc
	if(!source)
		return
	. += list(list(source, SLOT_OCCUPANCY_KEY))
	var/datum/ledger/from = dq_ledger(source)
	var/list/entry = from?.entries[thing]
	if(!entry)
		return
	var/id = entry[LEDGER_E_SLOT]
	var/datum/relation_definition/slot/def = from.def_by_id(id)
	if(def)
		. += def.removal_read_keys(source, thing, actor)
	. += op_transfer_read_keys(source, /datum/act/remove, thing, id, actor)

