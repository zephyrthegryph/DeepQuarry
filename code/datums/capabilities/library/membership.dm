// membership(joins =): what the holder is a member of while it exists (doc/rewrite/lifecycle.md "Starting state").
// Replaces DECLARE_REGISTRY (code/__defines/lifecycle_decl.dm) and REGISTRY_MEMBERSHIP for a type that is always
// a member; both stay until the codemod has moved their sites.
//
//	CAPABILITY(/obj/item/taperecorder, membership(joins = REGISTRY_LISTENING_OBJECTS))
//
// `joins` is one id or a list; each entry is either
//   - a registry id (REGISTRY_*, code/__defines/registries.dm): the holder is in that registry while materialized
//     (/atom/on_materialize() joins, on_dematerialize() leaves). A conditional registry is joined at materialize
//     too (DECLARE_REGISTRY did that); code may still registry_leave() / registry_join() it later;
//   - a /datum/system type: the holder is a MEMBER of that system while it exists (capability `joins`, the kernel's
//     membership store: cap_join_systems() at init, cap_leave_systems() at destroy).
// Two capabilities naming the same system are two sources; the holder leaves when the last goes.

/datum/capability/membership
	/// Registry ids (text) the holder is in while materialized. Shared: never written after construction.
	var/list/registries

/// Membership of registries (REGISTRY_* ids) and systems (/datum/system types): one entry or a list.
/proc/membership(joins)
	var/datum/capability/membership/C = new
	for(var/entry in (islist(joins) ? joins : list(joins)))
		if(ispath(entry, /datum/system))
			LAZYADD(C.joins, entry)
		else if(istext(entry))
			LAZYADD(C.registries, entry)
		else if(!isnull(entry))
			stack_trace("membership(joins = [entry]): neither a registry id nor a /datum/system type")
	C.key = "membership:[jointext(C.registries || list(), ",")]|[jointext(C.joins || list(), ",")]"
	return C

/// The registry ids A's capabilities make it a member of (membership(joins =)), or null. Per type (caps_of()).
/proc/cap_registries_of(atom/A)
	for(var/datum/capability/membership/C in caps_of(A))
		for(var/id in C.registries)
			LAZYOR(., id)
	// membership(joins =) in a CAPABILITIES block: the compiled table keeps it among its type-level capabilities.
	var/datum/type_table/T = table_of(A)
	for(var/key in T.caps)
		var/datum/capability/membership/declared = T.caps[key]
		if(!istype(declared))
			continue
		for(var/id in declared.registries)
			LAZYOR(., id)

/// Registry membership declared by capabilities (membership(joins =)) is the type's too: type_registries()
/// (cached per type) sees it, so on_materialize() joins and on_dematerialize() leaves it like REGISTRY_MEMBERSHIP.
/atom/declare_registries(list/ids)
	. = ..()
	for(var/id in cap_registries_of(src))
		ids |= id

/// A conditional registry named by membership(joins =) is joined at materialize as well (DECLARE_REGISTRY's rule).
/atom/join_registries()
	. = ..()
	for(var/id in cap_registries_of(src))
		var/datum/registry/registry = get_registry(id)
		if(registry?.conditional && !skips_registry(id))
			registry.add(src)
