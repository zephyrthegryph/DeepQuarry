/obj/item/grenade/flashbang
	name = "flashbang"
	icon_state = "flashbang"
	item_state = "flashbang"
	var/max_range = 10 //The maximum range possible, including species effect mods. Cuts off at 7 for normal humans. Should be 3 higher than your intended target range for affecting normal humans.
	var/banglet = 0

/obj/item/grenade/flashbang/detonate()
	..()
	for(var/obj/structure/closet/L in hear(max_range, get_turf(src)))
		if(locate(/mob/living/carbon/, L))
			for(var/mob/living/carbon/M in L) // ALLOW(latent): mobs are never latent
				bang(get_turf(src), M)

	for(var/mob/living/carbon/M in hear(max_range, get_turf(src)))
		bang(get_turf(src), M)

	for(var/obj/structure/blob/B in hear(max_range - 2,get_turf(src)))       		//Blob damage here
		var/damage = round(30/(get_dist(B,get_turf(src))+1))
		if(B.overmind)
			damage *= B.overmind.blob_type.burn_multiplier
		B.adjust_integrity(-damage)

	new/obj/effect/effect/smoke/illumination(loc, 5, 30, 30, "#FFFFFF")

	replace_with(src, /obj/effect/effect/sparks)

/obj/item/grenade/flashbang/proc/bang(turf/T , mob/living/carbon/M)					// Added a new proc called 'bang' that takes a location and a person to be banged.
	if(M.is_incorporeal())
		return

	to_chat(M, span_danger("BANG"))						// Called during the loop that bangs people in lockers/containers and when banging
	play_sfx(src, SFX_EFFECTS_BANG, extrarange = 30)		// people in normal view.  Could theroetically be called during other explosions.
																	// -- Polymorph

	//Checking for protections
	var/eye_safety = 0
	var/ear_safety = 0
	if(iscarbon(M))
		eye_safety = M.eyecheck()
		ear_safety = M.get_ear_protection()

	//Flashing everyone
	var/mob/living/carbon/human/H = M
	var/flash_effectiveness = 1
	var/bang_effectiveness = 1
	if(ishuman(M))
		flash_effectiveness = H.species.flash_mod
		bang_effectiveness = H.species.sound_mod
	if(eye_safety < 1 && get_dist(M, T) <= round(max_range * 0.7 * flash_effectiveness))
		M.flash_eyes()
		M.status_at_least(STAT_CONFUSED, 2 * flash_effectiveness)
		M.status_at_least(STAT_WEAKENED, 5 * flash_effectiveness)

	//Now applying sound
	if((get_dist(M, T) <= round(max_range * 0.3 * bang_effectiveness) || src.loc == M.loc || src.loc == M))
		if(ear_safety > 0)
			M.status_at_least(STAT_CONFUSED, 2)
			M.status_at_least(STAT_WEAKENED, 1)
		else
			M.status_at_least(STAT_CONFUSED, 10)
			M.status_at_least(STAT_WEAKENED, 3)
			if ((prob(14) || (M == src.loc && prob(70))))
				M.set_ear_damage(M.ear_damage + (rand(1, 10)))
			else
				M.set_ear_damage(M.ear_damage + (rand(0, 5)))
				M.status_at_least(STAT_DEAFENED, 15)
				M.deaf_loop.start() // Ear Ringing/Deafness

	else if(get_dist(M, T) <= round(max_range * 0.5 * bang_effectiveness))
		if(!ear_safety)
			M.status_at_least(STAT_CONFUSED, 8)
			M.set_ear_damage(M.ear_damage + (rand(0, 3)))
			M.status_at_least(STAT_DEAFENED, 10)
			M.deaf_loop.start() // Ear Ringing/Deafness

	else if(!ear_safety && get_dist(M, T) <= (max_range * 0.7 * bang_effectiveness))
		M.status_at_least(STAT_CONFUSED, 4)
		M.set_ear_damage(M.ear_damage + (rand(0, 1)))
		M.status_at_least(STAT_DEAFENED, 5)
		M.deaf_loop.start() // Ear Ringing/Deafness

	//This really should be in mob not every check
	if(ishuman(M))
		var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
		if (E && E.damage >= E.min_bruised_damage)
			to_chat(M, span_danger("Your eyes start to burn badly!"))
			if(!banglet && !(istype(src , /obj/item/grenade/flashbang/clusterbang)))
				if (E.damage >= E.min_broken_damage)
					to_chat(M, span_danger("You can't see anything!"))
	if (M.ear_damage >= 15)
		to_chat(M, span_danger("Your ears start to ring badly!"))
		if(!banglet && !(istype(src , /obj/item/grenade/flashbang/clusterbang)))
			if (prob(M.ear_damage - 10 + 5))
				to_chat(M, span_danger("You can't hear anything!"))
				M.set_sdisabilities(M.sdisabilities | (DEAF))
	else if(M.ear_damage >= 5)
		to_chat(M, span_danger("Your ears start to ring!"))

/obj/item/grenade/flashbang/clusterbang//Created by Polymorph, fixed by Sieve
	desc = "Use of this weapon may constiute a war crime in your area, consult your local " + JOB_SITE_MANAGER + "."
	name = "clusterbang"
	icon = 'icons/obj/grenade.dmi'
	icon_state = "clusterbang"
	var/can_repeat = TRUE		// Does this thing drop mini-clusterbangs?
	var/min_banglets = 4
	var/max_banglets = 8

/obj/item/grenade/flashbang/clusterbang/detonate()
	var/numspawned = rand(min_banglets, max_banglets)
	var/again = 0

	if(can_repeat)
		for(var/more = numspawned, more > 0, more--)
			if(prob(35))
				again++
				numspawned--

	for(var/do_spawn = numspawned, do_spawn > 0, do_spawn--)
		new /obj/item/grenade/flashbang/cluster(src.loc)//Launches flashbangs
		play_sfx(src, SFX_WEAPONS_ARMBOMB)

	for(var/do_again = again, do_again > 0, do_again--)
		new /obj/item/grenade/flashbang/clusterbang/segment(src.loc)//Creates a 'segment' that launches a few more flashbangs
		play_sfx(src, SFX_WEAPONS_ARMBOMB)
	consume(src)
	return

/obj/item/grenade/flashbang/clusterbang/segment
	desc = "A smaller segment of a clusterbang. Better run."
	name = "clusterbang segment"
	icon = 'icons/obj/grenade.dmi'
	icon_state = "clusterbang_segment_active" // segments only exist primed
	can_repeat = FALSE
	banglet = TRUE

/obj/item/grenade/flashbang/clusterbang/segment/Initialize(mapload) //Segments should never exist except part of the clusterbang, since these immediately 'do their thing' and asplode
	. = ..()

	var/stepdist = rand(1,4)//How far to step
	var/temploc = src.loc//Saves the current location to know where to step away from
	walk_away(src,temploc,stepdist)//I must go, my people need me

	after(src, rand(1.5 SECONDS, 6 SECONDS), PROC_REF(detonate)) // ALLOW(decl): the delay is rolled at random per instance, which a declaration cannot express

/obj/item/grenade/flashbang/cluster
	icon_state = "flashbang_active" // only exists primed
	banglet = TRUE

/obj/item/grenade/flashbang/cluster/Initialize(mapload)//Same concept as the segments, so that all of the parts don't become reliant on the clusterbang
	. = ..()

	var/stepdist = rand(1,3)
	var/temploc = src.loc
	walk_away(src,temploc,stepdist)

	after(src, rand(1.5 SECONDS, 6 SECONDS), PROC_REF(detonate)) // ALLOW(decl): the delay is rolled at random per instance, which a declaration cannot express

/obj/item/grenade/flashbang/clusterbang/primed
	desc = "This clusterbang seems to have already been activated. Uhoh."

/obj/item/grenade/flashbang/clusterbang/primed/Initialize(mapload)
	. = ..()
	activate()
