/// Was /datum/component/pollen_disability: a trait-granted disability ticking once a Life cycle.
CAPABILITY_TYPE(pollen_disability, CAP_DISABILITY_POLLEN, /datum/capability/disability/pollen, key = NONE)
/datum/capability/disability/pollen
	required_type = /mob/living/carbon/human
	var/allergy_chance = 20

/datum/capability/disability/pollen/disability_tick(mob/living/carbon/human/owner)

	if(QDELETED(owner))
		return
	if(!prob(allergy_chance))
		return
	if(!isturf(owner.loc))
		return
	if(owner.stat != CONSCIOUS)
		return
	if(owner.transforming)
		return

	// Check for masks or internals
	if(istype(owner.get_equipped_item(SLOT_ID_HEAD),/obj/item/clothing/head/helmet/space) && owner.internal) // Hardsuits
		return
	if(owner.get_equipped_item(SLOT_ID_MASK)) // masks block it entirely
		if(owner.get_equipped_item(SLOT_ID_MASK).item_flags & AIRTIGHT)
			if(owner.internal) // gas on
				return
		if(owner.get_equipped_item(SLOT_ID_MASK).item_flags & BLOCK_GAS_SMOKE_EFFECT)
			return

	// Time to ENGAGE THE ALLERGY
	if(prob(5) && istype(owner.loc,/turf/simulated/floor/grass))
		trigger_allergy(owner)
		return

	// Hand check
	var/list/things = list()
	if(prob(32))
		if(!isnull(owner.get_equipped_item(SLOT_ID_HAND_R)))
			things += owner.get_equipped_item(SLOT_ID_HAND_R)
		if(!isnull(owner.get_equipped_item(SLOT_ID_HAND_L)))
			things += owner.get_equipped_item(SLOT_ID_HAND_L)

	// terrain tests
	things += owner.loc.contents
	if(prob(25)) // ranged check
		things += orange(2,owner.loc)

	// scan irritants!
	if(things.len)
		if(locate_in_list(things, /obj/structure/flora))
			trigger_allergy(owner)
			return
		if(locate_in_list(things, /obj/effect/plant))
			trigger_allergy(owner)
			return
		for(var/obj/item/toy/bouquet/flowers in things)
			if(istype(flowers, /obj/item/toy/bouquet/fake)) //Plastic doesn't trigger pollen.
				continue
			trigger_allergy(owner)
			return
		for(var/obj/machinery/portable_atmospherics/hydroponics/irritant_tray in things)
			if(!irritant_tray.dead && !isnull(irritant_tray.seed))
				trigger_allergy(owner)
				return

/datum/capability/disability/pollen/proc/trigger_allergy(mob/living/carbon/human/owner)
	to_chat(owner, span_danger("[pick("The air feels itchy!","Your face feels uncomfortable!","Your body tingles!")]"))
	owner.apply_body_effect(/datum/body_effect/allergic_flare, 3 SECONDS)
