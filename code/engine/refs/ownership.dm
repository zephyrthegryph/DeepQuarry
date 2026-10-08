// Own (doc/rewrite/ownership.md §1): every owned entity has exactly one owner, recorded on
// the entity; owned vars are written only through the accessors here.
//
// The owner stamp is weak (the holder's ref text) so an owned child never keeps its owner
// alive: a holder and its children form no reference cycle. owner_of() re-checks that the
// holder still names the child, so a reused ref never answers.

/// The owner's weak key (own_key()), or null while unowned.
/datum/var/tmp/own_holder_ref
/// The owner's var holding this entity.
/datum/var/tmp/own_slot
/// This entity's weak key (own_key()), cached on first use.
/datum/var/tmp/own_key_text
#ifdef UNIT_TESTS
/// Test builds: the owner's type when it stamped this entity, so an orphan report names the real
/// owner even after its weak key was recycled by an unrelated datum.
/datum/var/tmp/own_holder_type
#endif

/// D's weak key, by which weak indexes name it (owner stamps, relation reverse indexes, keyed
/// links, OM handle slots): a string own_locate() turns back into D, which never keeps D alive.
/// It is D's ref in decimal, "<scramble>:<id>:<type>" ("3245:1200005:33" for [0x21124f85]),
/// computed once and cached on D. A turf's is its position ("<scramble>t<x>:<y>:<z>": ChangeTurf
/// keeps the position and resets vars, and a turf needs no ref at all). A key is unique among
/// live datums and recycled with the ref, exactly like the ref text it replaces.
///
/// Why not the ref text: BYOND 516's string table hashes little more than the first few
/// characters of a string, so strings that share a long prefix -- every "[0x21..." ref, every
/// sequential decimal -- land in one bucket and each new one costs time proportional to how many
/// are already alive. Keeping a ref string per entity (the audit and relation reverse indexes did)
/// made Southern Cross boot quadratic (measured in isolation, 100k kept refs ~19 s; these keys,
/// which lead with a fast-varying scramble, ~1 s).
/proc/own_key(datum/D)
	if(isnull(D))
		return null
	if(isdatum(D))
		. = D.own_key_text
		if(.)
			return
		if(isturf(D))
			var/turf/T = D
			. = "[(T.x * 31 + T.y * 7 + T.z) % 997]t[T.x]:[T.y]:[T.z]"
			T.own_key_text = .
			return
	var/r = "\ref[D]"
	var/n = length(r)
	// "[0x" + type digits + 6 id digits + "]"; anything else is kept as it is (starts with "[").
	if(n < 11 || text2ascii(r, 3) != 120)
		. = r
	else
		var/id = text2num(copytext(r, n - 6, n), 16)
		. = "[id % 9973]:[num2text(id, 8)]:[text2num(copytext(r, 4, n - 6), 16)]"
	if(isdatum(D))
		D.own_key_text = .

/// The datum an own_key() key names, or null.
/proc/own_locate(key)
	if(!istext(key))
		return null
	if(text2ascii(key, 1) == 91) // "[": a ref kept as it is
		return locate(key)
	var/turf_at = findtext(key, "t")
	if(turf_at)
		var/list/xyz = splittext(copytext(key, turf_at + 1), ":")
		return locate(text2num(xyz[1]), text2num(xyz[2]), text2num(xyz[3]))
	var/a = findtext(key, ":")
	var/b = findtext(key, ":", a + 1)
	if(!a || !b)
		return null
	return locate("\[0x[num2text(text2num(copytext(key, b + 1)), 1, 16)][num2text(text2num(copytext(key, a + 1, b)), 6, 16)]\]")

/// The entity's owner, or null (unowned, or its stamp is stale).
/proc/owner_of(datum/D)
	var/ref_text = D?.own_holder_ref
	if(!ref_text)
		return null
	var/datum/H = own_locate(ref_text)
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
	if(var_name == "contents") // built in: no assoc values, and a lookup is a "bad index"
		return FALSE
	for(var/key in L)
		if(!isnum(key) && L[key] == D)
			return TRUE
	return FALSE

/// Stamps D as owned by holder.var_name. FALSE (reported) when D already has another owner:
/// only own_transfer() moves an owned value.
/proc/own_stamp(datum/D, datum/holder, var_name)
	if(!isdatum(D))
		return TRUE
	var/holder_ref = OWN_KEY(holder)
	if(D.own_holder_ref)
		if(D.own_holder_ref == holder_ref && D.own_slot == var_name)
			return TRUE
		var/datum/current = owner_of(D)
		if(current)
			OWN_REPORT("[D.type] is already owned by [current.type].[D.own_slot]; adopting it into [holder.type].[var_name] needs own_transfer()")
			return FALSE
	D.own_holder_ref = holder_ref
	D.own_slot = var_name
	#ifdef UNIT_TESTS
	D.own_holder_type = holder.type
	#endif
	return TRUE

/// Clears D's owner stamp.
/proc/own_unstamp(datum/D)
	if(!isdatum(D))
		return
	D.own_holder_ref = null
	D.own_slot = null

/// The policy for holder.var_name's values now (a conditional policy proc or OWN_IF flag resolved).
/proc/own_policy(datum/holder, var_name, list/entry)
	var/policy = entry[OWNE_ARG]
	if(istext(policy) || ispath(policy))
		policy = call(holder, own_proc_name(policy))()
	else if(entry[OWNE_PARTNER] && !holder.vars[entry[OWNE_PARTNER]])
		policy = entry[OWNE_EXTRA]
	return policy

/// Disposes of an owned value leaving its var by policy: DELETE destroys it, SPILL moves a
/// movable still inside the holder to the drop location (anything else is destroyed),
/// CONTAINED leaves a movable to the holder's ledger slot, KEEP only lets it go. The value is
/// unstamped first.
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
		if(OWN_KEEP)
			return // released above: it outlives the holder
		if(OWN_HAND_OVER)
			var/list/hand_to = own_entry_successor(entry)
			var/datum/successor = hand_to ? holder.vars[hand_to[1]] : null
			if(isdatum(successor) && !QDELETED(successor) && (hand_to[2] in successor.vars))
				var/atom/movable/moving = value
				if(ismovable(moving) && isatom(successor) && moving.loc != successor)
					moving.containment_move(successor)
				rel_add(successor, hand_to[2], value)
				return
		if(OWN_CONTAINED)
			// A contained thing belongs to the holder's ledger slot: in the holder's teardown the
			// slot has already resolved it (phase 3), and one that left the contents is no longer
			// the holder's. Either way it is only let go here.
			return
		if(OWN_SPILL)
			var/atom/movable/AM = value
			var/atom/movable/H = holder
			if(ismovable(AM))
				if(ismovable(H) && AM.loc == H)
					var/atom/drop = H.containment_drop_location()
					if(drop && !QDELETED(drop))
						AM.containment_move(drop)
						AM.containment_redraw()
						return
				else if(AM.loc != H)
					return // it already left the holder: not the holder's to drop or delete
	ended_with(value, holder)

/// Owned-child release hook: `child` is leaving holder.var_name (disposed, taken or moved out),
/// still intact. For consequences outside the child: a media source's listeners, a tooltip's
/// client, an overmap marker. Must not sleep; call ..().
/datum/proc/on_owned_release(var_name, datum/child)
	SHOULD_NOT_SLEEP(TRUE)
	return

// ---------------------------------------------------------------- accessors

/// Adopts `value` into holder's one-shape owned var (rel_set() is the public verb). The previous value is
/// disposed of by policy (destroyed, spilled, or left contained). Returns `value`, or null when refused.
///
/// A CONTAINED var, or a value inside something else (a mob, a storage, a machine), is moved into the holder first
/// (own_wants_transfer(), transfer.dm); `into = FALSE` never moves it (own_transfer / own_move re-own in place). Putting
/// a thing somewhere on a player's or a script's behalf, with the checks, the release, the record and the log, is
/// move_into() (code/engine/declare/transfer.dm); the transfer arguments (user, slot, force, log) are gone from here.
/proc/_own_set(datum/holder, var_name, datum/value, into = null)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN)
	var/old = holder.vars[var_name]
	if(old == value)
		return value
	if(!isnull(value) && !own_guard(holder, value, "_own_set([var_name])")) // the one teardown guard (guard.dm)
		return null
	if(!own_type_ok(holder, var_name, entry, value))
		return null
	if(!isnull(value) && !own_bring_in(holder, var_name, value, entry, null, into, null, FALSE))
		return null
	if(entry && isdatum(value) && !own_stamp(value, holder, var_name))
		return null
	holder.vars[var_name] = value // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
	own_field_changed(holder, var_name)
	own_mark_changed(holder, var_name) // review 2 M8: every accessor write marks the holder
	if(entry && isdatum(old))
		own_dispose(holder, var_name, old, entry)
	return value

/// Detaches and returns holder.var_name's value, now unowned: the caller adopts it
/// (_own_set / _own_add elsewhere) or destroys it before returning.
/proc/own_take(datum/holder, var_name)
	var/datum/value = holder.vars[var_name]
	if(isnull(value))
		return null
	holder.vars[var_name] = null // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
	own_field_changed(holder, var_name)
	own_mark_changed(holder, var_name)
	holder.on_owned_release(var_name, value)
	own_unstamp(value)
	return value

/// Adds `value` to holder's owned list (created on first use). Returns `value`, or null when refused.
/// A movable somewhere else is moved in first: see _own_set() for `into`.
/proc/_own_add(datum/holder, var_name, datum/value, into = null)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN, TRUE)
	if(isnull(value))
		return null
	if(!own_guard(holder, value, "_own_add([var_name])")) // the one teardown guard (guard.dm)
		return null
	if(!own_type_ok(holder, var_name, entry, value))
		return null
	if(!own_bring_in(holder, var_name, value, entry, null, into, null, FALSE))
		return null
	if(entry && !own_stamp(value, holder, var_name))
		return null
	var/list/L = holder.vars[var_name]
	if(!islist(L))
		L = list()
		holder.vars[var_name] = L // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
		own_field_changed(holder, var_name)
	L |= value
	own_mark_changed(holder, var_name)
	return value

/// Removes `value` from holder's owned list and disposes of it by policy.
/proc/own_remove(datum/holder, var_name, datum/value)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN)
	var/list/L = holder.vars[var_name]
	if(!islist(L) || !(value in L))
		return FALSE
	L -= value
	own_mark_changed(holder, var_name)
	if(!length(L))
		holder.vars[var_name] = null // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
		own_field_changed(holder, var_name)
	if(entry)
		own_dispose(holder, var_name, value, entry)
	return TRUE

/// Values shape: holder.var_name[key] = value, disposing of the value it replaces. A movable
/// somewhere else is moved in first: see _own_set() for `into`.
/proc/_own_put(datum/holder, var_name, key, datum/value, into = null)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN, TRUE)
	if(!isnull(value) && !own_guard(holder, value, "_own_put([var_name])")) // the one teardown guard (guard.dm)
		return null
	if(!own_type_ok(holder, var_name, entry, value))
		return null
	var/list/L = holder.vars[var_name]
	if(!islist(L) && isnull(value))
		return null
	if(islist(L) && L[key] == value)
		return value
	if(!isnull(value) && !own_bring_in(holder, var_name, value, entry, null, into, null, FALSE))
		return null
	if(entry && isdatum(value) && !own_stamp(value, holder, var_name))
		return null
	if(!islist(L))
		L = list()
		holder.vars[var_name] = L // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
		own_field_changed(holder, var_name)
	var/old = L[key]
	if(isnull(value))
		L -= key
	else
		L[key] = value
	own_mark_changed(holder, var_name)
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
		own_list_emptied(holder, var_name) // a list declared `= list()` stays an empty list, a lazy one goes back to null
		own_field_changed(holder, var_name)
	if(value)
		own_mark_changed(holder, var_name)
		holder.on_owned_release(var_name, value)
	own_unstamp(value)
	return value

/// Moves an owned value from from.from_var to dest.dest_var: never destroyed or orphaned on the
/// way, and never moved (a re-own in place; _own_set() with a place to take it from is the
/// one-call transfer). `member` picks one member of a list/values var (the value, or its key); null moves a
/// one-shape var's value. A list/values destination adds (or puts under `dest_key`).
/proc/own_transfer(datum/from, from_var, datum/dest, dest_var, member = null, dest_key = null)
	// The one teardown guard (guard.dm), before anything is taken from `from`.
	var/datum/moving = isnull(member) ? from.vars[from_var] : member
	if(!own_guard(dest, isdatum(moving) ? moving : null, "own_transfer([from_var] -> [dest_var])"))
		return null
	// A move into a CONTAINED var is a transfer (transfer.dm): checked here, before anything is taken,
	// so a refusal leaves the value with `from` instead of destroying it below.
	if(isdatum(moving) && own_wants_transfer(dest, dest_var, moving, own_table_of(dest).entries[dest_var], into = FALSE) && own_transfer_refusal(dest, moving))
		return null
	var/datum/value = isnull(member) ? own_take(from, from_var) : own_take_member(from, from_var, member)
	if(isnull(value))
		return null
	var/adopted
	if(!isnull(dest_key))
		adopted = _own_put(dest, dest_var, dest_key, value, into = FALSE)
	else if(islist(dest.vars[dest_var]) || own_table_of(dest).entries[dest_var]?[OWNE_LIST])
		adopted = _own_add(dest, dest_var, value, into = FALSE)
	else
		adopted = _own_set(dest, dest_var, value, into = FALSE)
	if(!adopted)
		OWN_REPORT("own_transfer of [value.type] from [from.type].[from_var] to [dest.type].[dest_var] refused; destroying it")
		spent(value)
	return adopted

/// Moves `value` into dest.dest_var from wherever it is owned now (own_transfer() from its current
/// owner), or adopts it when nothing owns it. For a hand-off whose source slot the caller doesn't
/// name (an expedition mission passed through a generation job, a gift's contents).
/proc/own_move(datum/value, datum/dest, dest_var, dest_key = null)
	if(!isdatum(value))
		return null
	if(!own_guard(dest, value, "own_move([dest_var])")) // the one teardown guard (guard.dm)
		return null
	var/datum/current = owner_of(value)
	if(current)
		if(current == dest && value.own_slot == dest_var)
			return value
		var/list/cur = current.vars[value.own_slot]
		return own_transfer(current, value.own_slot, dest, dest_var, islist(cur) ? value : null, dest_key)
	if(!isnull(dest_key))
		return _own_put(dest, dest_var, dest_key, value, into = FALSE)
	if(islist(dest.vars[dest_var]) || own_table_of(dest).entries[dest_var]?[OWNE_LIST])
		return _own_add(dest, dest_var, value, into = FALSE)
	return _own_set(dest, dest_var, value, into = FALSE)

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
	// A list declared `= list()` is emptied in place, not nulled: code that reads `L.len` on it
	// keeps working after the take. A lazy list (declared null) goes back to null (own_list_emptied).
	if(islist(value))
		var/list/L = value
		L.Cut()
		own_list_emptied(holder, var_name)
	else
		holder.vars[var_name] = null // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
	own_field_changed(holder, var_name)
	for(var/datum/child as anything in .)
		holder.on_owned_release(var_name, child)
		own_unstamp(child)

/// An owned list var was just emptied. A lazy list (the var's declared value is null) goes back to
/// null, as the LAZY* macros leave it: an empty list is truthy, so `if(component_parts)`-style
/// "not built yet" checks and "dropped everything" checks (isnull) read it wrong. A list declared
/// `= list()` stays an empty list for code that reads its length.
/proc/own_list_emptied(datum/holder, var_name)
	if(isnull(initial(holder.vars[var_name])))
		holder.vars[var_name] = null // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name

/// Disposes of everything holder.var_name owns, by policy (or `policy` when given).
/proc/own_clear(datum/holder, var_name, policy = null)
	var/list/entry = own_entry_of_kind(holder, var_name, OWNK_OWN)
	var/value = holder.vars[var_name]
	if(isnull(value))
		return
	if(!islist(value))
		holder.vars[var_name] = null // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
		own_field_changed(holder, var_name)
		if(entry)
			own_dispose(holder, var_name, value, entry, policy)
		return
	var/list/L = value
	var/list/copy = var_name == "contents" ? own_contents_members(holder) : L.Copy()
	if(var_name != "contents") // built in: its members leave by moving, never by a cut
		L.Cut() // emptied in place (see own_take_all); own_teardown() nulls a lazy one afterwards
		own_field_changed(holder, var_name)
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
	if(var_name == "contents")
		return own_contents_members(holder)
	. = list()
	var/value = holder.vars[var_name]
	if(isdatum(value))
		. += value
	else if(islist(value))
		var/list/L = value
		if(var_name == "contents") // built in, never assoc: indexing it by a thing is a bad index
			for(var/datum/thing as anything in L)
				. += thing
			return
		for(var/key in L)
			if(isdatum(key))
				. += key
			if(!isnum(key))
				var/datum/child = L[key]
				if(isdatum(child))
					. += child

/// What an `owns(nameof(contents), ...)` declaration owns: the holder's contents, less the movables
/// another owned var of the holder names (an attached accessory, a suit's hood): those are
/// disposed of by their own var's policy, not spilled with the rest. `contents` is a built-in
/// list with no associated values (indexing it by an object is a "bad index" runtime), so it is
/// only ever walked by member.
/proc/own_contents_members(atom/holder)
	. = list()
	if(!isatom(holder))
		return
	var/holder_ref = own_key(holder)
	FOR_CONTENTS(var/atom/movable/thing, holder)
		if(thing.own_holder_ref == holder_ref && thing.own_slot && thing.own_slot != "contents")
			continue
		. += thing

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
		H.vars[var_name] = null // ALLOW(api): the ownership accessor clears the var as part of releasing the owned value
		own_field_changed(H, var_name)
		return
	if(var_name == "contents")
		return // built in: the dying thing leaves by moving, never by a cut or an index
	if(islist(value))
		var/list/L = value
		L -= D
		for(var/key in L.Copy())
			if(!isnum(key) && L[key] == D)
				L -= key

/// A contained or spilled owned movable left its owner's contents (the ledger's note_exit()): the
/// contents slot was its ownership, so the owner's var lets it go (no dispose: it is intact and
/// somewhere else now). A DELETE-policy movable child keeps its owner wherever it goes.
/proc/own_contents_exit(atom/holder, atom/movable/thing)
	if(thing.own_holder_ref != own_key(holder) || QDELETED(thing))
		return
	var/var_name = thing.own_slot
	var/list/entry = own_table_of(holder).entries[var_name]
	if(!entry)
		return
	var/policy = own_policy(holder, var_name, entry)
	if(policy != OWN_CONTAINED && policy != OWN_SPILL)
		return
	holder.on_owned_release(var_name, thing)
	own_release_member(holder, var_name, thing)
	own_unstamp(thing)

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
			var/atom/drop = AM.containment_drop_location()
			if(!drop || QDELETED(drop))
				spent(thing)
			else
				thing.containment_move(drop)
				thing.containment_redraw()

/// Takes `value` out of holder.var_name without disposing of it.
/proc/own_release_member(datum/holder, var_name, datum/value)
	var/current = holder.vars[var_name]
	if(current == value)
		holder.vars[var_name] = null // ALLOW(api): the ownership accessor clears the var as part of releasing the owned value
		own_field_changed(holder, var_name)
	else if(var_name == "contents")
		return // built in: a member leaves by moving (the caller moves it), never by a cut
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
		D.ownership_field_disposed(var_name)
	// Only once every child is disposed of: a dying child's own teardown may still read its
	// owner's (now empty) list, e.g. `length(master.ability_objects - src)`.
	for(var/var_name in T.own_vars)
		if(islist(D.vars[var_name]) && var_name != "contents" && !length(D.vars[var_name]))
			own_list_emptied(D, var_name)
	for(var/var_name in T.proto_vars)
		proto_teardown(D, var_name)
	rx_teardown(D)

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

/// Extra runtime ownership can preserve the declared field cleanup order.
/datum/proc/ownership_field_disposed(var_name)
	return
