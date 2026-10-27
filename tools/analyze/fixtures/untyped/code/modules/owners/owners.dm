// Procs are judged by the type that owns them and their name, never by the name alone.

// --- same-named procs on unrelated types: a call that passes an entity to one does not judge the other
/datum/own_a/proc/scale(n)
	return n

/datum/own_a/proc/use_a()
	return scale(3)

/datum/own_b/proc/scale(n)
	return n

/datum/own_b/proc/use_b(datum/thing/T)
	return scale(T)

/datum/own_holder
	var/from_a
	var/from_b

/datum/own_holder/proc/fill(datum/own_a/A, datum/own_b/B, datum/thing/T)
	from_a = A.use_a()
	from_b = B.use_b(T)

// --- a local named like a proc is a local, not a mention of the proc
/proc/clash_target(n)
	return n

/proc/clash_user()
	var/clash_target = 2
	return clash_target(clash_target)

/datum/local_holder
	var/from_local

/datum/local_holder/proc/fill()
	from_local = clash_user()

// --- a PROC_REF reaches the type it names (and the types below it), not a same-named proc elsewhere
/datum/ref_a/proc/tick(n)
	return n

/datum/ref_a/proc/use_a()
	return tick(1)

/datum/ref_a/proc/hook()
	return PROC_REF(tick)

/datum/ref_a/sub/tick(n)
	return n

/datum/ref_a/sub/use_sub()
	return tick(1)

/datum/ref_b/proc/tick(n)
	return n

/datum/ref_b/proc/use_b()
	return tick(1)

/datum/ref_c/proc/tock(n)
	return n

/datum/ref_c/proc/use_c()
	return tock(1)

/datum/ref_d/proc/tock(n)
	return n

/datum/ref_d/proc/use_d()
	return tock(1)

/proc/hook_d()
	return TYPE_PROC_REF(/datum/ref_d, tock)

/datum/ref_holder
	var/from_a
	var/from_sub
	var/from_b
	var/from_c
	var/from_d

/datum/ref_holder/proc/fill(datum/ref_a/A, datum/ref_a/sub/S, datum/ref_b/B, datum/ref_c/C, datum/ref_d/D)
	from_a = A.use_a()
	from_sub = S.use_sub()
	from_b = B.use_b()
	from_c = C.use_c()
	from_d = D.use_d()
