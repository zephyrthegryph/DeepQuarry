/datum/holder
	var/list/datum/parts
	var/datum/scalar
	var/list/image/pics
	var/list/datum/declared_parts

CAPABILITIES(/datum/holder)
	owns_many(nameof(parts), /datum)

/datum/holder/proc/fill(datum/thing, mob/user, var_name, loose, datum/holder/other)
	own_add(src, nameof(parts), thing, user = user)
	own_add(src, nameof(parts), thing, into = 1)
	own_add(src, nameof(parts), thing, null, 1)
	own_add(src, nameof(parts))
	var/ref = GLOBAL_PROC_REF(own_add)
	#define LATER(x) own_add(src, nameof(parts), x)
	// a var that cannot be declared stays as it is
	own_add(src, var_name, thing)
	own_add(src, nameof(pics), thing)
	own_add(src, nameof(scalar), thing)
	own_add(src, nameof(not_a_var), thing)
	own_add(loose, nameof(parts), thing)
	// the plain form beside them still converts
	rel_add(src, nameof(parts), thing)
