/datum/component/drippy
	var/drip_chance = 5
	var/blood_color = "#A10808"

/datum/component/drippy/Initialize()
	if(!isliving(parent))
		return COMPONENT_INCOMPATIBLE

/datum/component/drippy/RegisterWithParent()
	add_trait_life_system(parent, /datum/life_system/trait/drippy)
	RegisterSignal(parent, COMSIG_HUMAN_DNA_FINALIZED, PROC_REF(create_color))

/datum/component/drippy/UnregisterFromParent()
	UnregisterSignal(parent, COMSIG_HUMAN_DNA_FINALIZED)
	remove_trait_life_system(parent, /datum/life_system/trait/drippy)

/datum/component/drippy/proc/process_component()
	SIGNAL_HANDLER
	var/mob/living/living_guy = parent
	if(QDELETED(parent))
		return
	if(!prob(drip_chance))
		return
	if(isbelly(living_guy.loc))
		return
	if(living_guy.stat == DEAD)
		return
	if(living_guy.inStasisNow())
		return
	var/turf/T = get_turf(living_guy.loc)
	if(!isturf(T))
		return
	var/obj/effect/decal/cleanable/blood/B
	var/decal_type = /obj/effect/decal/cleanable/blood/splatter

	// Are we dripping or splattering?
	var/list/drips = list()
	// Only a certain number of drips (or one large splatter) can be on a given turf.
	for(var/obj/effect/decal/cleanable/blood/drip/drop in T)
		LAZYOR(drips, drop.drips)
		qdel(drop)
	if(drips.len < 4)
		decal_type = /obj/effect/decal/cleanable/blood/drip

	// Find a blood decal or create a new one.
	B = locate(decal_type) in T
	if(!B)
		B = new decal_type(T)

	var/obj/effect/decal/cleanable/blood/drip/drop = B
	if(istype(drop) && drips && drips.len)
		drop.add_overlay(drips)
		LAZYOR(drop.drips, drips)

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

/datum/component/drippy/proc/create_color()
	SIGNAL_HANDLER
	if(ishuman(parent))
		var/mob/living/carbon/human/temp_human = parent
		blood_color = rgb(temp_human.r_skin,temp_human.g_skin,temp_human.b_skin)

/// Trait system: dripping. Was a COMSIG_LIVING_LIFE listener.
/datum/life_system/trait/drippy
	name = "drippy"
	component_type = /datum/component/drippy

/datum/life_system/trait/drippy/tick_component(mob/living/self, datum/component/drippy/component)
	component.process_component()
