/// Membership as relations (doc/rewrite/kernel.md sec 2.4).
///
/// One store holds every MEMBER relation: (key, member) with a source count and an optional role. A key is
/// a /datum/system type (a capability's `joins`) or a capability type (a work item's `members =`). It
/// replaces three hand-kept rosters:
///   - `/datum/system/members` + `member_index` (now member_list() / kernel_join() / kernel_leave() wrappers),
///   - `/datum/cap_system/roles/by_role` (now cap_system_members() / cap_system_role() wrappers),
///   - the `world_services()` hand list (now derived from the registry, world_services() in world_lanes.dm).
///
/// Joining twice from different sources is one membership held by two sources: it ends when the last
/// source leaves (`join(system, E, source)` of the shared interface). Join and leave are O(1): the last
/// member takes the freed slot (swap-remove).

/datum/kernel_membership
	/// key -> list of members, in join order (the list a system's member_list() returns; read only).
	var/list/members_by_key = list()
	/// key -> assoc member -> index in members_by_key[key].
	var/list/index_by_key = list()
	/// key -> assoc member -> assoc source -> TRUE (sources holding this membership).
	var/list/sources_by_key = list()
	/// key -> assoc member -> role.
	var/list/role_by_key = list()
	/// key -> assoc role text -> list of members holding it (role-indexed keys only).
	var/list/roles_by_key = list()
	/// member -> list of keys it belongs to, for teardown and systems_of().
	var/list/keys_of = list()

/// The one membership store.
/proc/kernel_membership()
	var/static/datum/kernel_membership/store = new
	return store

/// Adds `member` to `key` held by `source` (null: an anonymous source). Returns TRUE when the member was not
/// in `key` before, so on_join() should run. A second source on an existing member only records the source.
/// `role` (optional) indexes the member for members_of(key, role); a later join may change it.
/proc/member_join(key, datum/member, source = null, role = null)
	var/datum/kernel_membership/M = kernel_membership()
	if(!key || !member)
		return FALSE
	var/list/index = M.index_by_key[key]
	if(!index)
		index = M.index_by_key[key] = list()
		M.members_by_key[key] = list()
		M.sources_by_key[key] = list()
		M.role_by_key[key] = list()
	var/list/sources = M.sources_by_key[key]
	var/src_key = source || member
	var/list/held = sources[member]
	var/is_new = !index[member]
	if(!held)
		held = sources[member] = list()
	held[src_key] = TRUE
	if(!isnull(role))
		member_set_role(M, key, member, role)
	if(!is_new)
		return FALSE
	var/list/members = M.members_by_key[key]
	members += member
	index[member] = length(members)
	var/list/keys = M.keys_of[member]
	if(!keys)
		keys = M.keys_of[member] = list()
	keys += key
	return TRUE

/// Puts `member` under `role` in `key`, moving it out of its old role list.
/proc/member_set_role(datum/kernel_membership/M, key, datum/member, role)
	var/list/role_of = M.role_by_key[key]
	role = "[role]"
	var/old = role_of[member]
	if(!isnull(old) && old == role)
		return
	var/list/role_lists = M.roles_by_key[key]
	if(!role_lists)
		role_lists = M.roles_by_key[key] = list()
	if(!isnull(old))
		var/list/old_list = role_lists[old]
		old_list -= member
	var/list/new_list = role_lists[role]
	if(!new_list)
		new_list = role_lists[role] = list()
	new_list += member
	role_of[member] = role

/// Removes `source`'s hold on `member` in `key` (null: the anonymous source; `all`: every source). Returns TRUE
/// when the member left `key` (its last source went), so on_leave() should run.
/proc/member_leave(key, datum/member, source = null, all = FALSE)
	var/datum/kernel_membership/M = kernel_membership()
	var/list/index = M.index_by_key[key]
	var/at = index?[member]
	if(!at)
		return FALSE
	var/list/sources = M.sources_by_key[key]
	var/list/held = sources[member]
	if(!all)
		held -= (source || member)
		if(length(held))
			return FALSE
	var/list/members = M.members_by_key[key]
	var/last = length(members)
	var/datum/moved = members[last]
	members[at] = moved
	index[moved] = at
	members.len = last - 1
	index -= member
	sources -= member
	var/list/role_of = M.role_by_key[key]
	var/role = role_of[member]
	if(!isnull(role))
		var/list/role_list = M.roles_by_key[key][role]
		role_list -= member
		role_of -= member
	var/list/keys = M.keys_of[member]
	if(keys)
		keys -= key
		if(!length(keys))
			M.keys_of -= member
	return TRUE

/// True when `member` is in `key`.
/proc/member_is(key, datum/member)
	var/datum/kernel_membership/M = kernel_membership()
	return !!M.index_by_key[key]?[member]

/// The members of `key`, in join order. The store's own list: read it, never write it. With `role`, the members
/// holding that role instead.
/proc/members_of(key, role = null)
	var/datum/kernel_membership/M = kernel_membership()
	if(isnull(role))
		return M.members_by_key[key] || list()
	var/list/by_role = M.roles_by_key[key]
	return by_role?["[role]"] || list()

/// How many members `key` has.
/proc/members_total(key)
	var/datum/kernel_membership/M = kernel_membership()
	return length(M.members_by_key[key])

/// The role `member` holds in `key`, or null.
/proc/member_role(key, datum/member)
	var/datum/kernel_membership/M = kernel_membership()
	return M.role_by_key[key]?[member]

/// Every key `member` belongs to (a copy).
/proc/member_keys(datum/member)
	var/datum/kernel_membership/M = kernel_membership()
	var/list/keys = M.keys_of[member]
	return keys ? keys.Copy() : list()

/// Removes `member` from every key it is in (a destroyed datum). Returns the keys it left.
/proc/member_purge(datum/member)
	. = member_keys(member)
	for(var/key in .)
		member_leave(key, member, all = TRUE)
	return .
