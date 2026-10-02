/obj/benchy
	var/energy = 1
	var/other = 2

/obj/benchy/derived()
	. += runs_while(nameof(energy))

/obj/benchy/should_run()
	return energy + other

/obj/benchy/reactions()
	. += every(1 SECONDS, PROC_REF(zzz), members = /datum/capability/bench)

/mob/living/life_hud_darksight()
	return 1
