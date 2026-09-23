// Registries (roadmap L3, doc/rewrite/state.md section 7). The API and how to
// use it is at the top of code/__defines/registries.dm.

/// Every registry, as id -> /datum/registry. Built once from the declarations
/// in code/datums/registry_declarations.dm.
GLOBAL_LIST_INIT(registries, build_registries())
/// Every registry's member list, as id -> list. REGISTRY_MEMBERS() reads it.
/// The lists are the registries' own, so a read costs one lookup.
GLOBAL_LIST_INIT(registry_members, registry_member_lists())
/// type -> the registries its instances join (an empty list for most types).
GLOBAL_LIST_EMPTY(registries_by_type)

/proc/build_registries()
	// GLOB is still being built while globals initialize, so the shared
	// result lives in a plain global until both GLOB lists hold it.
	var/global/list/built
	if(built)
		return built
	built = list()
	. = built
	for(var/datum/registry/path as anything in subtypesof(/datum/registry))
		var/datum/registry/registry = new path
		if(!registry.id)
			stack_trace("[path] has no id")
			continue
		if(.[registry.id])
			stack_trace("duplicate registry id [registry.id]")
			continue
		.[registry.id] = registry

/proc/registry_member_lists()
	var/list/registries = build_registries()
	. = list()
	for(var/id in registries)
		var/datum/registry/registry = registries[id]
		.[id] = registry.members

/// The registry with this id. Crashes on an unknown id: a typo would otherwise
/// read as an always-empty list.
/proc/get_registry(id)
	RETURN_TYPE(/datum/registry)
	var/datum/registry/registry = GLOB.registries[id]
	if(!registry)
		CRASH("unknown registry [id]")
	return registry

/// Members of a keyed registry filed under key. Read-only; may be null.
/proc/registry_keyed(id, key)
	var/datum/registry/registry = get_registry(id)
	return registry.members_by_key?[key]

/// A set of live instances. See code/__defines/registries.dm.
/datum/registry
	/// Unique id, one of the REGISTRY_* defines.
	var/id
	/// Live members in join order.
	var/list/members
	/// Keyed registries only: key -> list of members, each in join order.
	var/list/members_by_key
	/// Keyed registries only: member -> the key it is filed under.
	var/list/member_keys
	/// Set on registries that file members by registry_key().
	var/keyed = FALSE

/datum/registry/New()
	members = list()
	if(keyed)
		members_by_key = list()
		member_keys = list()

/// Joins a member. Only /atom/join_registries() calls this.
/datum/registry/proc/add(atom/member)
	members += member
	if(keyed)
		file_member(member)

/// Leaves a member. Only /atom/leave_registries() calls this.
/datum/registry/proc/remove(atom/member)
	members -= member
	if(keyed)
		unfile_member(member)

/// The live member list, in join order. Read-only.
/datum/registry/proc/members()
	return members

/// How many live members there are.
/datum/registry/proc/count()
	return length(members)

/// Re-files a member whose key (registry_key()) changed, e.g. a new frequency.
/datum/registry/proc/rekey(atom/member)
	if(!keyed || !(member in member_keys))
		return
	unfile_member(member)
	file_member(member)

/datum/registry/proc/file_member(atom/member)
	PRIVATE_PROC(TRUE)
	var/key = member.registry_key(id)
	member_keys[member] = key
	if(isnull(key))
		return
	LAZYADD(members_by_key[key], member)

/datum/registry/proc/unfile_member(atom/member)
	PRIVATE_PROC(TRUE)
	var/key = member_keys[member]
	member_keys -= member
	if(isnull(key))
		return
	LAZYREMOVE(members_by_key[key], member)
	if(!members_by_key[key])
		members_by_key -= key

// ---- Membership ----

/// Adds the ids of every registry this type's instances join to `ids`.
/// Declare with REGISTRY_MEMBERSHIP(); overrides must call parent.
/atom/proc/declare_registries(list/ids)
	SHOULD_CALL_PARENT(TRUE)
	return

/// Instance-level opt-out, decided by state set in Initialize() and fixed for
/// the object's life (e.g. an energy ball's miniballs). Keep it rare and cheap.
/atom/proc/skips_registry(registry_id)
	return FALSE

/// A keyed registry files this member under the returned key (null: unfiled).
/atom/proc/registry_key(registry_id)
	return null

/// The registries this atom's type joins, cached per type.
/atom/proc/type_registries()
	var/list/cached = GLOB.registries_by_type[type]
	if(cached)
		return cached
	var/list/ids = list()
	declare_registries(ids)
	cached = list()
	for(var/id in ids)
		cached |= get_registry(id)
	GLOB.registries_by_type[type] = cached
	return cached

/// Joins the declared registries. Only /atom/on_materialize() calls this.
/atom/proc/join_registries()
	PRIVATE_PROC(TRUE)
	for(var/datum/registry/registry as anything in type_registries())
		if(!skips_registry(registry.id))
			registry.add(src)

/// Leaves the declared registries. Only /atom/on_dematerialize() calls this.
/atom/proc/leave_registries()
	PRIVATE_PROC(TRUE)
	for(var/datum/registry/registry as anything in type_registries())
		if(!skips_registry(registry.id))
			registry.remove(src)
