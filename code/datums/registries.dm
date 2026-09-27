// Registries (roadmap L3, doc/rewrite/state.md section 7). The API and how to
// use it is at the top of code/__defines/registries.dm.

/// Every registry, as id -> /datum/registry. Built once from the declarations
/// in code/datums/registry_declarations.dm.
GLOBAL_LIST_INIT(registries, build_registries())
/// Every registry's member list, as id -> list. REGISTRY_MEMBERS() reads it.
/// The lists are the registries' own, so a read costs one lookup.
GLOBAL_LIST_INIT(registry_members, registry_member_lists())
/// type -> the registries its instances join (an empty list for most types).
/// The same list as registries_by_type_table(), which works before GLOB is
/// built (datums created while globals initialize join registries too).
GLOBAL_LIST_INIT(registries_by_type, registries_by_type_table())

/proc/registries_by_type_table()
	var/static/list/by_type = list()
	return by_type

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
	var/datum/registry/registry = build_registries()[id]
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
	/// Set on registries whose members join and leave by state (alive, logged
	/// in, switched on) through registry_join()/registry_leave(), instead of
	/// for their whole materialized life. Declared types may join; everyone
	/// leaves automatically when dematerialized or deleted.
	var/conditional = FALSE
	/// Conditional registries only: member -> TRUE, for O(1) membership.
	var/list/present

/datum/registry/New()
	members = list()
	if(keyed)
		members_by_key = list()
		member_keys = list()
	if(conditional)
		present = list()

/// Joins a member. Only join_registries() and registry_join() call this.
/datum/registry/proc/add(datum/member)
	if(conditional)
		if(present[member])
			return
		present[member] = TRUE
	members += member
	if(keyed)
		file_member(member)

/// Leaves a member. Only leave_registries() and registry_leave() call this.
/datum/registry/proc/remove(datum/member)
	if(conditional)
		if(!present[member])
			return
		present -= member
	members -= member
	if(keyed)
		unfile_member(member)

/// TRUE if `member` is in this registry.
/datum/registry/proc/has(datum/member)
	return conditional ? !!present[member] : (member in members)

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

/datum/registry/proc/file_member(datum/member)
	PRIVATE_PROC(TRUE)
	var/key = registry_key(member, id)
	member_keys[member] = key
	if(isnull(key))
		return
	LAZYADD(members_by_key[key], member)

/datum/registry/proc/unfile_member(datum/member)
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
/datum/proc/declare_registries(list/ids)
	SHOULD_CALL_PARENT(TRUE)
	return

/// Instance-level opt-out, decided by state set in Initialize() and fixed for
/// the object's life (e.g. an energy ball's miniballs, a preview dummy). Keep
/// it rare and cheap.
/datum/proc/skips_registry(registry_id)
	return FALSE

/// A keyed registry files this member under the returned key (null: unfiled).
/proc/registry_key(datum/source, registry_id)
	return null

/// The registries this datum's type joins, cached per type.
/datum/proc/type_registries()
	var/list/by_type = registries_by_type_table()
	var/list/cached = by_type[type]
	if(cached)
		return cached
	var/list/ids = list()
	declare_registries(ids)
	cached = list()
	for(var/id in ids)
		cached |= get_registry(id)
	by_type[type] = cached
	return cached

/// Joins the declared (non-conditional) registries. /atom/on_materialize()
/// calls this; a datum that isn't an atom calls it from its own New().
/datum/proc/join_registries()
	for(var/datum/registry/registry as anything in type_registries())
		if(!registry.conditional && !skips_registry(registry.id))
			registry.add(src)

/// Leaves every declared registry, conditional ones included.
/// /atom/on_dematerialize() calls this; the destroy transaction calls it for
/// every other datum (dq_lifecycle_leave_registries()), so a deleted member
/// is never left behind and nothing removes itself by hand.
/proc/leave_registries(datum/source)
	for(var/datum/registry/registry as anything in source.type_registries())
		if(!source.skips_registry(registry.id))
			registry.remove(source)

/// Puts `member` in conditional registry `id` (idempotent). Its type must
/// declare REGISTRY_MEMBERSHIP() for `id`. It leaves again with
/// registry_leave(), or by itself when dematerialized or deleted.
/proc/registry_join(id, datum/member)
	var/datum/registry/registry = get_registry(id)
	if(!member || QDELETED(member))
		return FALSE
	if(!registry.conditional)
		CRASH("registry_join() on [id], which isn't conditional: declare REGISTRY_MEMBERSHIP() instead")
	if(!(registry in member.type_registries()))
		CRASH("[member.type] joins [id] without declaring REGISTRY_MEMBERSHIP()")
	if(member.skips_registry(id))
		return FALSE
	registry.add(member)
	return TRUE

/// Takes `member` out of conditional registry `id` (a no-op if it isn't in).
/proc/registry_leave(id, datum/member)
	var/datum/registry/registry = get_registry(id)
	if(member)
		registry.remove(member)

/// registry_join() when `in_it`, registry_leave() otherwise.
/proc/registry_set(id, datum/member, in_it)
	if(in_it)
		return registry_join(id, member)
	registry_leave(id, member)
	return FALSE

/// TRUE if `member` is in registry `id`.
/proc/registry_has(id, datum/member)
	var/datum/registry/registry = get_registry(id)
	return registry.has(member)

/// Destroy transaction, phase 2 for datums that aren't atoms (atoms leave on
/// dematerialize): drop `D` from every registry its type declares.
/proc/dq_lifecycle_leave_registries(datum/D)
	if(isatom(D))
		return
	var/list/registries = registries_by_type_table()[D.type]
	if(registries && !length(registries))
		return // cached: this type joins nothing
	leave_registries(D)
