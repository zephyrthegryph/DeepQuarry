//CORTICAL BORER ORGANS.
/obj/item/organ/internal/borer
	name = "cortical borer"
	icon = 'icons/obj/objects.dmi'
	icon_state = "borer"
	organ_tag = O_BRAIN
	desc = "A disgusting space slug."
	parent_organ = BP_HEAD
	vital = 1

/obj/item/organ/internal/borer/organ_tick(cycles)
	if(!owner || !owner.reagents)
		return

	// Borer husks regenerate health, feel no pain, and are resistant to stuns and brain damage.
	for(var/chem in list(REAGENT_ID_TRICORDRAZINE,REAGENT_ID_TRAMADOL,REAGENT_ID_HYPERZINE,REAGENT_ID_ALKYSINE))
		if(owner.reagents.get_reagent_amount(chem) < 3)
			owner.reagents.add_reagent(chem, 5)

	// They're also super gross and ooze ichor.
	if(prob(5))
		var/mob/living/carbon/human/H = owner
		if(!istype(H))
			return

		var/datum/reagent/blood/B = locate_in_list(H.vessel.reagent_list, /datum/reagent/blood)
		blood_splatter(H,B,1)
		var/obj/effect/decal/cleanable/blood/splatter/goo = locate_within(get_turf(owner), /obj/effect/decal/cleanable/blood/splatter)
		if(goo)
			goo.name = "husk ichor"
			goo.desc = "It's thick and stinks of decay."
			goo.set_basecolor("#412464")

/obj/item/organ/internal/borer/removed(mob/living/user)
	var/mob/living/prev_owner = owner

	..()

	var/mob/living/simple_mob/animal/borer/B = prev_owner?.has_brain_worms()
	if(B)
		B.leave_host()
		move_player(prev_owner, B, "borer organ removed from [prev_owner]")

	expire(0)

//VOX ORGANS.
/obj/item/organ/internal/stack
	name = "cortical stack"
	parent_organ = BP_HEAD
	icon_state = "brain_prosthetic"
	organ_tag = "stack"
	vital = TRUE

/obj/item/organ/internal/stack/vox/stack
	name = "vox cortical stack"
	icon_state = "cortical_stack"

// This organ has work every organ_tick(), so the body's organ clock stays running for it.
/obj/item/organ/internal/borer/life_step_idle()
	return FALSE

