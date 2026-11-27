/datum/thing
	var/num = 1
	var/datum/thing/next
	var/list/items
/datum/thing/proc/act(a, b)
	return a
/datum/thing/proc/operator+(x)
	return src
/datum/other
/proc/undefined_names()
	world.log << missing_var
	missing_proc()
	world.log << global.missing_global
	global.missing_global_proc()
/proc/static_types(x)
	world.log << x.num
	x.act()
	var/datum/thing/T = new
	world.log << T.nope
	T.nope()
	world.log << T.next.next.num
	var/datum/nonexistent/N
	world.log << N
	var/P = /datum/missing
	world.log << P
	new /datum/missing()
/proc/implicit_new()
	var/x = new
	world.log << x
/datum/thing/act(a, b)
	..()
	return b
/datum/other/proc/lonely()
	..()
/proc/iterate()
	var/datum/D
	for(var/atom/A in D)
		world.log << A
	var/datum/thing/T
	for(var/atom/A in T)
		world.log << A
	var/list/L = list()
	for(var/atom/A in L)
		world.log << A
	for(var/k, v in T)
		world.log << k
/proc/operators()
	var/datum/other/O = new
	O++
	--O
	var/datum/thing/T = new
	T++
	var/list/L = list()
	L++
/proc/static_access()
	world.log << /datum/thing::num
	world.log << /datum/thing::nope
	world.log << /datum/missing::num
	var/datum/thing/T
	world.log << T::num
	world.log << /datum/thing::act()
	world.log << /datum/thing::nothing()
/proc/catches()
	try
		world.log << "a"
	catch(var/exception/E)
		world.log << E
