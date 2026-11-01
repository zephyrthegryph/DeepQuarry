/proc/bundle_one(atom/A)
	var/datum/capability/lockable/L = new
	return list(L)
/proc/bundle_two(atom/A)
	return bundle_one(A)
/proc/bundle_three(atom/A)
	return list(bundle_two(A))
/proc/helper_only(atom/A)
	return cap_of(A, 1)
/proc/commented_only(atom/A)
	// new /datum/capability/x
	return "new /datum/capability/y"
/proc/cap_multi(
		list/a,
		b)
	return
/datum/thing/proc/bundle_one()
	return
