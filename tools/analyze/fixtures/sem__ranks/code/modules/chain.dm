// An acyclic derive chain and a handler over it: the generated table carries the handler's rank.
/datum/act
	var/datum/holder

/datum/act/eval
	var/dt

/obj/machinery/chain
	var/base = 0
	var/c1 = 0
	var/c2 = 0
	var/c3 = 0
	var/obj/machinery/chain/next

REL(/obj/machinery/chain, next)
TRACKED(/obj/machinery/chain, base)

CAPABILITIES(/obj/machinery/chain,
	when(PROC_REF(ready)),
	when(PROC_REF(raw)))

/obj/machinery/chain/proc/derive_c1()
	return base + 1

/obj/machinery/chain/proc/derive_c2()
	return c1 + 1

/obj/machinery/chain/proc/derive_c3()
	return c2 + c1 + (next ? next.c1 : 0)

/// Reads the deepest derived value: rank 3.
/obj/machinery/chain/proc/ready(datum/act/eval/A)
	return c3 > 2

/// Reads only base state: rank 0.
/obj/machinery/chain/proc/raw(datum/act/eval/A)
	return base > 0

/proc/tracked_changed(datum/E, name)
	return TRUE
