/datum/base/proc/named(alpha, beta)
	return
/datum/base/child/named(alpha)
	return
/datum/base/other/named(alpha, beta, gamma)
	return
/proc/kw()
	var/datum/base/B = new
	B.named(beta = 1)
	B.named(beta = 2)
	B.named(delta = 1)
	B.named(alpha = 1, 2)
	animate(B, alpha = 1, 2)
	var/datum/base/child/C = new
	C.named(gamma = 3)
/proc/ops(L, x)
	world.log << (!x in L)
	world.log << (x = 1 in L)
	world.log << (!x & 1)
	world.log << (!x | 1)
	world.log << (!x ^ 1)
/proc/input_types()
	var/mob/M = input("x") as mob
	var/n = input("x") as num
	var/t = input("x") as text|null
	world.log << M.name + n + t
/proc/locates()
	var/turf/T = locate(1, 2, 3)
	world.log << T.x
/proc/astypes(datum/D)
	var/mob/M = astype(D, /mob)
	world.log << M.ckey
/proc/return_types()
	var/list/L = block(locate(1, 1, 1), locate(2, 2, 2))
	for(var/turf/T in L)
		world.log << T.x
	var/regex/R = regex("x")
	world.log << R.nope
	var/turf/S = get_step(usr, NORTH)
	world.log << S.nope
/proc/selfcalls()
	. = ..()
	return .()
/mob/proc/protected_thing()
	set SpacemanDMM_protected_proc = TRUE
	return
/proc/calls_protected(mob/M)
	M.protected_thing()
/proc/var_in_list()
	var/list/turf/L
	var/turf/T = L[1]
	world.log << T.nope
