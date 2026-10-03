/datum/trait_state/drippy
	life_stage = /datum/om/stage/life/trait/drippy
	var/drip_chance = 5
	var/blood_color = "#A10808"

/datum/trait_state/drippy/attach()
	..()
	observe(owner, /datum/notice/human_dna_finalized, src, then(PROC_REF(create_color)))

/datum/trait_state/drippy/life_tick()
	var/mob/living/living_guy = owner
	if(QDELETED(living_guy))
		return
	if(!prob(drip_chance))
		return
	if(isbelly(living_guy.loc))
		return
	var/turf/T = get_turf(living_guy.loc)
	if(!isturf(T))
		return
	var/obj/effect/decal/cleanable/blood/B
	var/decal_type = /obj/effect/decal/cleanable/blood/splatter

	// Are we dripping or splattering?
	var/list/drips = list()
	// Only a certain number of drips (or one large splatter) can be on a given turf.
	for(var/obj/effect/decal/cleanable/blood/drip/drop in turf_contents_of_type(T, /obj/effect/decal/cleanable/blood/drip))
		drips |= drop.drips
		qdel(drop)
	if(drips.len < 4)
		decal_type = /obj/effect/decal/cleanable/blood/drip

	// Find a blood decal or create a new one.
	B = locate_on(T, decal_type)
	if(!B)
		B = new decal_type(T)

	var/obj/effect/decal/cleanable/blood/drip/drop = B
	if(istype(drop) && drips && drips.len)
		drop.add_overlay(drips)
		drop.drips |= drips

	B.basecolor = blood_color
	B.update_icon()
	if(istype(B, drop)) //We're a drop.
		B.name = "drips of something"
	else //We're a puddle.
		B.name = "puddle of something"
	B.desc = "It's thick and gooey. Perhaps it's the chef's cooking?"
	B.dryname = "dried something"
	B.drydesc = "It's dry and crusty. The janitor isn't doing their job."
	dq_set_fluorescent(B, 0)
	B.invisibility = INVISIBILITY_NONE

/datum/trait_state/drippy/proc/create_color(datum/act/notice/A)
	EVENT_HANDLER
	if(ishuman(owner))
		var/mob/living/carbon/human/temp_human = owner
		blood_color = rgb(temp_human.r_skin,temp_human.g_skin,temp_human.b_skin)

/// Trait system: dripping.
/datum/om/stage/life/trait/drippy
	name = "drippy"
	state_type = /datum/trait_state/drippy
	// P2-S6: paused stasis frames and dead bodies skip it.
	run_if = LIFE_RUN_IF_PLACED_LIVE_BIOLOGY
