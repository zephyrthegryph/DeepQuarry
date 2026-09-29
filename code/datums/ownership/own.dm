// Own (doc/rewrite/ownership.md §1): every owned entity has exactly one owner, recorded on
// the entity; owned vars are written only through the accessors here.
//
// The owner stamp is weak (the holder's ref text) so an owned child never keeps its owner
// alive: a holder and its children form no reference cycle. owner_of() re-checks that the
// holder still names the child, so a reused ref never answers.

/// The owner's ref text, or null while unowned.
/datum/var/tmp/own_holder_ref
/// The owner's var holding this entity.
/datum/var/tmp/own_slot

#ifdef UNIT_TESTS
/// Test builds: ref text -> TRUE for every stamped entity (own_audit() walks it).
GLOBAL_LIST_EMPTY(own_audit_index)
#endif

/// The entity's owner, or null (unowned, or its stamp is stale).
/proc/owner_of(datum/D)
	var/ref_text = D?.own_holder_ref
	if(!ref_text)
		return null
	var/datum/H = locate(ref_text)
	if(!isdatum(H) || !own_names(H, D.own_slot, D))
		return null
	return H

/// The var of owner_of(D) that holds D, or null.
/proc/owner_slot_of(datum/D)
	return owner_of(D) ? D.own_slot : null

/// TRUE when holder.var_name holds D (as the value, a list member or an assoc value).
/proc/own_names(datum/holder, var_name, datum/D)
	if(!(var_name in holder.vars))
		return FALSE
	var/value = holder.vars[var_name]
	if(value == D)
		return TRUE
	if(!islist(value))
		return FALSE
	var/list/L = value
	if(D in L)
		return TRUE
	for(var/key in L)
		if(!isnum(key) && L[key] == D)
			return TRUE
	return FALSE

/// Stamps D as owned by holder.var_name. FALSE (reported) when D already has another owner:
/// only own_transfer() moves an owned value.
/proc/own_stamp(datum/D, datum/holder, var_name)
	if(!isdatum(D))
		return TRUE
	var/holder_ref = ref(holder)
	if(D.own_holder_ref)
		if(D.own_holder_ref == holder_ref && D.own_slot == var_name)
			return TRUE
		var/datum/current = owner_of(D)
		if(current)
			OWN_REPORT("[D.type] is already owned by [current.type].[D.own_slot]; adopting it into [holder.type].[var_name] needs own_transfer()")
			return FALSE
	if(QDELETED(holder))
		OWN_REPORT("[holder.type].[var_name] adopting [D.type] while being destroyed")
	D.own_holder_ref = holder_ref
	D.own_slot = var_name
	#ifdef UNIT_TESTS
	GLOB.own_audit_index[ref(D)] = TRUE
	#endif
	return TRUE

/// Clears D's owner stamp.
/proc/own_unstamp(datum/D)
	if(!isdatum(D))
		return
	D.own_holder_ref = null
	D.own_slot = null
	#ifdef UNIT_TESTS
	GLOB.own_audit_index -= ref(D)
	#endif

/// The policy for holder.var_name's values now (a conditional policy proc or OWN_IF flag resolved).
/proc/own_policy(datum/holder, var_name, list/entry)
	var/policy = entry[OWNE_ARG]
	if(ispath(policy))
		policy = call(holder, own_proc_name(policy))()
	else if(entry[OWNE_PARTNER] && !holder.vars[entry[OWNE_PARTNER]])
		policy = entry[OWNE_EXTRA]
	return policy

/// Disposes of an owned value leaving its var by policy: DELETE destroys it, SPILL moves a
/// movable still inside the holder to the drop location (anything else is destroyed),
/// CONTAINED leaves a movable to the holder's ledger slot. The value is unstamped first.
/proc/own_dispose(datum/holder, var_name, datum/value, list/entry, policy)
	if(!isdatum(value))
		return
	holder.on_owned_release(var_name, value)
	own_unstamp(value)
	if(QDELETED(value))
		return
	if(isnull(policy))
		policy = own_policy(holder, var_name, entry)
	switch(policy)
		if(OWN_CONTAINED)
			// During the holder's own teardown the ledger slot has already resolved it (phase 3:
			// deleted, spilled or transferred), so it is only let go here.
			var/atom/movable/AM = value
			if(!QDELETED(holder) && (!ismovable(AM) || AM.loc != holder))
				OWN_REPORT("[holder.type].[var_name] is CONTAINED but [value.type] is not in its contents (loc [ismovable(AM) ? AM.loc?.type : "n/a"])")
			return
		if(OWN_SPILL)
			var/atom/movable/AM = value
			var/atom/movable/H = holder
			if(ismovable(AM) && ismovable(H) && AM.loc == H)
				var/atom/drop = H.drop_location()
				if(drop && !QDELETED(drop))
					AM.forceMove(drop)
					AM.update_icon()
					return
	qdel(value)

/// Owned-child release hook: `child` is leaving holder.var_name (disposed, taken or moved out),
/// still intact. For consequences outside the child: a media source's listeners, a tooltip's
/// client, an overmap marker. Must not sleep; call ..().
/datum/proc/on_owned_release(var_name, datum/child)
	SHOULD_NOT_SLEEP(TRUE)
	return

// ---------------------------------------------------------------- accessors

/// Adopts `value` into holder's one-shape owned var. The previous value is disposed of by
/// policy (destroyed, spilled, or left contained). Returns `value`, or null when refused.
/proc/own_set(datum/holder, var_name, datum/value)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN)
	var/old = holder.vars[var_name]
	if(old == value)
		return value
	if(entry && isdatum(value))
		if(!own_stamp(value, holder, var_name))
			return null
		if(own_policy(holder, var_name, entry) == OWN_CONTAINED)
			var/atom/movable/AM = value
			if(!ismovable(AM) || AM.loc != holder)
				OWN_REPORT("[holder.type].[var_name] is CONTAINED: put [value.type] in its contents before own_set()")
	holder.vars[var_name] = value // ALLOW(ownership): the accessor
	if(entry && isdatum(old))
		own_dispose(holder, var_name, old, entry)
	return value

/// Detaches and returns holder.var_name's value, now unowned: the caller adopts it
/// (own_set / own_add elsewhere) or destroys it before returning.
/proc/own_take(datum/holder, var_name)
	var/datum/value = holder.vars[var_name]
	if(isnull(value))
		return null
	holder.vars[var_name] = null // ALLOW(ownership): the accessor
	holder.on_owned_release(var_name, value)
	own_unstamp(value)
	return value

/// Adds `value` to holder's owned list (created on first use). Returns `value`, or null when refused.
/proc/own_add(datum/holder, var_name, datum/value)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN, TRUE)
	if(isnull(value))
		return null
	if(entry && !own_stamp(value, holder, var_name))
		return null
	var/list/L = holder.vars[var_name]
	if(!islist(L))
		L = list()
		holder.vars[var_name] = L // ALLOW(ownership): the accessor
	L |= value
	return value

/// Removes `value` from holder's owned list and disposes of it by policy.
/proc/own_remove(datum/holder, var_name, datum/value)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN)
	var/list/L = holder.vars[var_name]
	if(!islist(L) || !(value in L))
		return FALSE
	L -= value
	if(!length(L))
		holder.vars[var_name] = null // ALLOW(ownership): the accessor
	if(entry)
		own_dispose(holder, var_name, value, entry)
	return TRUE

/// Values shape: holder.var_name[key] = value, disposing of the value it replaces.
/proc/own_put(datum/holder, var_name, key, datum/value)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN, TRUE)
	var/list/L = holder.vars[var_name]
	if(!islist(L))
		if(isnull(value))
			return null
		L = list()
		holder.vars[var_name] = L // ALLOW(ownership): the accessor
	var/old = L[key]
	if(old == value)
		return value
	if(entry && isdatum(value) && !own_stamp(value, holder, var_name))
		return null
	if(isnull(value))
		L -= key
	else
		L[key] = value
	if(entry && isdatum(old))
		own_dispose(holder, var_name, old, entry)
	return value

/// List or values shape: detaches one member (a value, or the value under a key) and returns it unowned.
/proc/own_take_member(datum/holder, var_name, value_or_key)
	var/list/L = holder.vars[var_name]
	if(!islist(L))
		return null
	var/datum/value = null
	if(isdatum(value_or_key) && (value_or_key in L) && isnull(L[value_or_key]))
		value = value_or_key
		L -= value
	else if(!isnull(value_or_key) && !isnum(value_or_key) && (value_or_key in L))
		value = L[value_or_key]
		L -= value_or_key
	if(!length(L))
		holder.vars[var_name] = null // ALLOW(ownership): the accessor
	if(value)
		holder.on_owned_release(var_name, value)
	own_unstamp(value)
	return value

/// Moves an owned value from from.from_var to dest.dest_var: never destroyed or orphaned on the
/// way. `member` picks one member of a list/values var (the value, or its key); null moves a
/// one-shape var's value. A list/values destination adds (or puts under `dest_key`).
/proc/own_transfer(datum/from, from_var, datum/dest, dest_var, member = null, dest_key = null)
	var/datum/value = isnull(member) ? own_take(from, from_var) : own_take_member(from, from_var, member)
	if(isnull(value))
		return null
	var/adopted
	if(!isnull(dest_key))
		adopted = own_put(dest, dest_var, dest_key, value)
	else if(islist(dest.vars[dest_var]) || (!isnull(member) && isnull(dest.vars[dest_var])))
		adopted = own_add(dest, dest_var, value)
	else
		adopted = own_set(dest, dest_var, value)
	if(!adopted)
		OWN_REPORT("own_transfer of [value.type] from [from.type].[from_var] to [dest.type].[dest_var] refused; destroying it")
		qdel(value)
	return adopted

/// Moves `value` into dest.dest_var from wherever it is owned now (own_transfer() from its current
/// owner), or adopts it when nothing owns it. For a hand-off whose source slot the caller doesn't
/// name (an expedition mission passed through a generation job, a gift's contents).
/proc/own_move(datum/value, datum/dest, dest_var, dest_key = null)
	if(!isdatum(value))
		return null
	var/datum/current = owner_of(value)
	if(current)
		if(current == dest && value.own_slot == dest_var)
			return value
		var/list/cur = current.vars[value.own_slot]
		return own_transfer(current, value.own_slot, dest, dest_var, islist(cur) ? value : null, dest_key)
	if(!isnull(dest_key))
		return own_put(dest, dest_var, dest_key, value)
	if(islist(dest.vars[dest_var]))
		return own_add(dest, dest_var, value)
	return own_set(dest, dest_var, value)

/// Detaches everything holder.var_name owns and returns it as a list, all unowned (the caller
/// adopts or destroys each). The var is emptied.
/proc/own_take_all(datum/holder, var_name)
	. = own_values(holder, var_name)
	var/value = holder.vars[var_name]
	if(isnull(value))
		return
	if(islist(value) && var_name == "contents")
		OWN_REPORT("own_take_all on [holder.type].contents: move things out through the ledger")
		return list()
	holder.vars[var_name] = null // ALLOW(ownership): the accessor
	for(var/datum/child as anything in .)
		holder.on_owned_release(var_name, child)
		own_unstamp(child)

/// Disposes of everything holder.var_name owns, by policy (or `policy` when given).
/proc/own_clear(datum/holder, var_name, policy = null)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN)
	var/value = holder.vars[var_name]
	if(isnull(value))
		return
	if(!islist(value))
		holder.vars[var_name] = null // ALLOW(ownership): the accessor
		if(entry)
			own_dispose(holder, var_name, value, entry, policy)
		return
	var/list/L = value
	var/list/copy = L.Copy()
	if(var_name != "contents") // built in: its members leave by moving, never by a cut
		L.Cut()
		holder.vars[var_name] = null // ALLOW(ownership): the accessor
	if(!entry)
		return
	for(var/key in copy)
		var/datum/child = isnum(key) ? null : copy[key]
		if(isdatum(child))
			own_dispose(holder, var_name, child, entry, policy)
		if(isdatum(key))
			own_dispose(holder, var_name, key, entry, policy)

/// Every value holder.var_name owns (one, members, or assoc values), as a new list.
/proc/own_values(datum/holder, var_name)
	. = list()
	var/value = holder.vars[var_name]
	if(isdatum(value))
		. += value
	else if(islist(value))
		var/list/L = value
		for(var/key in L)
			if(isdatum(key))
				. += key
			if(!isnum(key))
				var/datum/child = L[key]
				if(isdatum(child))
					. += child

// ---------------------------------------------------------------- lifecycle

/// Phase 2: a dying owned entity leaves its owner's var, so no owner keeps a reference to it
/// (a cell deleted in its APC, a board in its machine). No dispose: it is already dying.
/proc/own_release_from_owner(datum/D)
	var/datum/H = owner_of(D)
	if(!H)
		own_unstamp(D)
		return
	var/var_name = D.own_slot
	own_unstamp(D)
	if(QDELETED(H) && H.gc_destroyed != GC_CURRENTLY_BEING_QDELETED)
		return
	var/value = H.vars[var_name]
	if(value == D)
		H.vars[var_name] = null // ALLOW(ownership): lifecycle release
		return
	if(islist(value))
		var/list/L = value
		L -= D
		for(var/key in L.Copy())
			if(!isnum(key) && L[key] == D)
				L -= key

/// Phase 3, for a movable: SPILL-policy owned movables still inside go to the drop location.
/proc/own_spill_phase(atom/movable/AM)
	var/datum/own_table/T = own_table_of(AM)
	if(!T.own_vars)
		return
	for(var/var_name in T.own_vars)
		var/list/entry = T.entries[var_name]
		if(own_policy(AM, var_name, entry) != OWN_SPILL)
			continue
		for(var/datum/value as anything in own_values(AM, var_name))
			var/atom/movable/thing = value
			if(!ismovable(thing) || thing.loc != AM || QDELETED(thing))
				continue
			own_release_member(AM, var_name, thing)
			own_unstamp(thing)
			var/atom/drop = AM.drop_location()
			if(!drop || QDELETED(drop))
				qdel(thing)
			else
				thing.forceMove(drop)
				thing.update_icon()

/// Takes `value` out of holder.var_name without disposing of it.
/proc/own_release_member(datum/holder, var_name, datum/value)
	var/current = holder.vars[var_name]
	if(current == value)
		holder.vars[var_name] = null // ALLOW(ownership): lifecycle release
	else if(islist(current))
		var/list/L = current
		L -= value
		for(var/key in L.Copy())
			if(!isnum(key) && L[key] == value)
				L -= key

/// Phase 4: every owned var disposed of by policy.
/proc/own_teardown(datum/D)
	var/datum/own_table/T = own_table_of(D)
	for(var/var_name in T.own_vars)
		if(!isnull(D.vars[var_name]))
			own_clear(D, var_name)
	for(var/var_name in T.proto_vars)
		proto_teardown(D, var_name)

/// Phase 8: an owned var holding a value again was re-set during teardown. Delete it and say so.
/proc/own_scrub(datum/D)
	var/datum/own_table/T = own_table_of(D)
	for(var/var_name in T.own_vars)
		var/value = D.vars[var_name]
		if(isnull(value) || (islist(value) && !length(value)))
			continue
		OWN_REPORT("[D.type].[var_name] re-set during teardown; deleting what it holds")
		own_clear(D, var_name, OWN_DELETE)
	for(var/var_name in T.proto_vars)
		if(proto_is_private(D, var_name))
			OWN_REPORT("[D.type].[var_name] (proto) re-set to a private copy during teardown; deleting it")
			proto_teardown(D, var_name)
	for(var/var_name in T.ref_vars)
		rel_clear(D, var_name)
