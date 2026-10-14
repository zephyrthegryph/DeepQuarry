/datum/holder
	var/datum/cell
	var/list/items
	var/untyped_thing
	var/datum/declared_one

CAPABILITIES(/datum/holder)
	owns_one(nameof(cell), /datum)

/datum/holder/proc/fill(datum/thing, mob/user, var_name, loose, datum/holder/other)
	own_set(src, nameof(cell), thing, user = user)
	own_set(src, nameof(cell), thing, into = 1)
	own_set(src, nameof(cell), thing, null, 1)
	own_set(src, nameof(cell))
	var/ref = GLOBAL_PROC_REF(own_set)
	#define LATER(x) own_set(src, nameof(cell), x)
	// a var that cannot be declared stays as it is
	own_set(src, var_name, thing)
	own_set(src, nameof(untyped_thing), thing)
	own_set(src, nameof(items), list())
	own_set(src, nameof(not_a_var), thing)
	own_set(loose, nameof(cell), thing)
	// the plain form beside them still converts
	rel_set(src, nameof(cell), thing)
