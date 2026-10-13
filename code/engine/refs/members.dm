// Many relations over a plain list or an alist (doc/rewrite/proposals/reference_storage.md).
//
// A many relation var (ref_many / owns_many) holds its members in one of three shapes:
//
//   plain list   ordered members, or text keys to members (the original shapes). Membership of a long ref_many list is read from the reverse
//                index (rel_list_holds()), not by scanning the list; removing one member scans, at the engine's list speed.
//   alist set    `var/alist/members = alist()`: member -> TRUE. Membership, add and remove are constant time; the order is the hash's, so a
//                reader that needs an order keeps a plain list. `for(var/x in members)` walks the members as it does a list.
//   alist map    a keyed many: key -> member, the key a number, text or path (a plain list cannot take a number as a key: `L[5]` is an index).
//                A member may sit under several keys. The holder remembers each member's keys (rel_keys_of()), so a member that leaves
//                (removed, or deleted) takes all its keys with it in constant time, with no scan of the map.
//
// islist() is FALSE for an alist, so every branch of the relation core asks REL_LISTLIKE() instead. An alist var is declared with its initial
// value (`var/alist/members = alist()`) and a keyed put into a null var with a numeric key makes one; the write verbs (rel_add, rel_remove,
// rel_clear, rel_take) work on all three shapes alike.

/datum/rx_state
	/// Keyed many relations: var name -> alist of member key (own_key(), weak) -> the key (or a list of keys) the member sits under in that var.
	var/list/rel_keys

/// The members of a many relation container as a new list of datums: a list's elements, an alist set's keys, an alist map's values. A member
/// under several keys is listed once.
/proc/rel_list_members(L)
	if(!istype(L, /alist))
		var/list/plain = L
		return plain.Copy()
	. = list()
	var/alist/seen = alist()
	for(var/key, value in L)
		if(isdatum(key) && !seen[key])
			seen[key] = TRUE
			. += key
		if(isdatum(value) && !seen[value])
			seen[value] = TRUE
			. += value

/// TRUE when holder.var_name's container `L` holds `member` (as a list member, an alist key, or an alist value under some key). A long plain list
/// asks the member's reverse index, so adding a member to a big ref_many does not scan it.
/proc/rel_list_holds(list/L, datum/holder, var_name, datum/member)
	if(istype(L, /alist))
		return (member in L) || !isnull(rel_keys_of(holder, var_name, member))
	if(length(L) <= REL_SCAN_MAX)
		return member in L
	. = rel_names(holder, var_name, member)
	#ifdef UNIT_TESTS
	// The index is written with the view: it must agree with the list (checked while the list is small enough that the scan costs nothing).
	if(length(L) <= 256 && . != (member in L))
		OWN_REPORT("[holder.type].[var_name]: the reverse index says [. ? "a member is present" : "a member is absent"] but the list disagrees; something wrote the list outside rel_add()/rel_remove()")
	#endif

// ---------------------------------------------------------------- the key index of a keyed many

/// Records that `member` sits under `key` in holder.var_name. A datum key is not recorded (it would be a strong reference in a weak index).
/proc/rel_keys_note(datum/holder, var_name, datum/member, key)
	if(isnull(key) || isdatum(key) || !isdatum(member))
		return
	var/datum/rx_state/rx = rx_of(holder)
	var/alist/index = rx.rel_keys?[var_name]
	if(!index)
		LAZYINITLIST(rx.rel_keys)
		index = alist()
		rx.rel_keys[var_name] = index
	var/mkey = OWN_KEY(member)
	var/current = index[mkey]
	if(isnull(current))
		index[mkey] = key
	else if(islist(current))
		var/list/keys = current
		keys |= key
	else if(current != key)
		index[mkey] = list(current, key)

/// The key `member` sits under in holder.var_name (a list of them when it sits under several), or null. Reads the holder's index only.
/proc/rel_keys_of(datum/holder, var_name, datum/member)
	var/datum/rx_state/rx = holder.rx
	if(!rx?.rel_keys)
		return null
	var/alist/index = rx.rel_keys[var_name]
	if(!index || !isdatum(member))
		return null
	return index[OWN_KEY(member)]

/// `member` no longer sits under `key` in holder.var_name.
/proc/rel_keys_forget(datum/holder, var_name, datum/member, key)
	var/datum/rx_state/rx = holder.rx
	var/alist/index = rx?.rel_keys?[var_name]
	if(!index || !isdatum(member))
		return
	var/mkey = OWN_KEY(member)
	var/current = index[mkey]
	if(isnull(current))
		return
	if(islist(current))
		var/list/keys = current
		keys -= key
		if(length(keys) == 1)
			index[mkey] = keys[1]
		else if(!length(keys))
			index -= mkey
	else if(current == key)
		index -= mkey
	if(!length(index))
		rel_keys_clear(holder, var_name)

/// `member` sits under no key in holder.var_name any more.
/proc/rel_keys_forget_all(datum/holder, var_name, datum/member)
	var/datum/rx_state/rx = holder.rx
	var/alist/index = rx?.rel_keys?[var_name]
	if(!index || !isdatum(member))
		return
	index -= OWN_KEY(member)
	if(!length(index))
		rel_keys_clear(holder, var_name)

/// holder.var_name holds no keyed member any more.
/proc/rel_keys_clear(datum/holder, var_name)
	var/datum/rx_state/rx = holder.rx
	if(!rx?.rel_keys)
		return
	rx.rel_keys -= var_name
	UNSETEMPTY(rx.rel_keys)

/// Every key `member` sits under in holder.var_name, as a new list (empty when none).
/proc/rel_keys_list(datum/holder, var_name, datum/member)
	var/current = rel_keys_of(holder, var_name, member)
	if(isnull(current))
		return list()
	if(islist(current))
		var/list/keys = current
		return keys.Copy()
	return list(current)

/// Takes `member` out of the alist `L` of holder.var_name wherever it sits (as a key of a set, under every key of a map) and forgets its keys.
/// Writes only the container: the callers do the relation bookkeeping.
/proc/rel_alist_remove(alist/L, datum/holder, var_name, datum/member)
	L -= member
	var/current = rel_keys_of(holder, var_name, member)
	if(isnull(current))
		return
	var/list/to_remove = islist(current) ? rel_keys_list(holder, var_name, member) : list(current)
	for(var/key in to_remove)
		if(L[key] == member)
			L -= key
	rel_keys_forget_all(holder, var_name, member)

// ---------------------------------------------------------------- keyed ref_many (an alist map of references)

/// Puts `target` under `key` in the keyed ref_many holder.var_name (an alist map; made when the var is null). A member already under that key
/// is replaced (it stays linked while it sits under another key of the same var). Returns the target, or null when refused.
/proc/_rel_map_put(datum/source, var_name, datum/target, key, list/entry)
	if(isdatum(key))
		OWN_REPORT("[source.type].[var_name]: a keyed many takes a number, text or path as a key, not [key]")
		return null
	if(entry[OWNE_PARTNER] && entry[OWNE_ARG] != RELS_PLAIN)
		OWN_REPORT("[source.type].[var_name]: a keyed many cannot be paired (back =); key the references on each side separately")
		return null
	var/alist/L = source.vars[var_name]
	if(isnull(L))
		L = alist()
		source.vars[var_name] = L // ALLOW(api): this proc is the accessor: the one place allowed to write this var by name
	else if(!istype(L, /alist))
		OWN_REPORT("[source.type].[var_name]: holds a plain list; a keyed many is an alist (declare it `= alist()`)")
		return null
	var/old = L[key]
	if(old == target)
		return target
	if(isdatum(old))
		_rel_map_drop_key(source, var_name, L, key, entry, FALSE)
	var/first = isnull(rel_keys_of(source, var_name, target))
	L[key] = target
	rel_keys_note(source, var_name, target, key)
	own_field_changed(source, var_name)
	if(first)
		_rel_index(target, source, var_name)
		if(entry[OWNE_WATCH])
			_rel_watch(target, source)
	return target

/// Takes whatever sits under `key` out of the keyed ref_many `L`. The member is unlinked (indexes, watch, on_unlink) once its last key is gone.
/// Returns the member that was there, or null.
/proc/_rel_map_drop_key(datum/source, var_name, alist/L, key, list/entry, notify = TRUE)
	var/old = L[key]
	if(!(key in L))
		return null
	L -= key
	if(!isdatum(old))
		return null
	var/datum/member = old
	rel_keys_forget(source, var_name, member, key)
	if(notify)
		own_field_changed(source, var_name)
	if(isnull(rel_keys_of(source, var_name, member)) && !(member in L))
		_rel_unindex(member, source, var_name)
		if(entry?[OWNE_WATCH])
			_rel_unwatch(member, source)
		_rel_unlinked(source, member, entry)
	return member
