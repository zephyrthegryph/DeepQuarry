// Hop kinds (doc/rewrite/final_api.html section 7, "Hop kinds"; code/modules/unit_tests/dq_hop_tests.dm).
//
// The container hop: a lamp's stat and its on_change hook read what the crate it lies in holds ("loc.hop_lit"). The move choke point publishes
// loc, and the crate's own var reaches what is inside it.

/obj/hop_crate
	name = "hop crate"
	var/hop_lit = FALSE

TRACKED(/obj/hop_crate, hop_lit)

/obj/hop_lamp
	name = "hop lamp"
	/// How many times the hook heard the crate flip.
	var/hop_heard = 0

STAT(/obj/hop_lamp, hop_level, SUM)

CAPABILITIES(/obj/hop_lamp)
	contributes(STAT_HOP_LEVEL, PROC_REF(crate_level))
	on_change("loc.hop_lit", ANY, then(PROC_REF(crate_flipped)))

/// 5 in a lit crate, 1 in any other (including none). The generated reads of this proc are the stat's inputs: loc, loc.hop_lit.
/obj/hop_lamp/proc/crate_level(datum/act/A)
	if(!istype(loc, /obj/hop_crate))
		return 1
	var/obj/hop_crate/C = loc
	return C.hop_lit ? 5 : 1

/obj/hop_lamp/proc/crate_flipped(datum/act/A)
	hop_heard++
