/datum/component/pollen_disability
	var/mob/living/carbon/human/owner
	var/allergy_chance = 20

/datum/component/pollen_disability/Initialize()
	if (!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

	owner = parent
	RegisterSignal(owner, COMSIG_HANDLE_DISABILITIES, PROC_REF(process_component))

/datum/component/pollen_disability/proc/process_component()
	SIGNAL_HANDLER

	if(QDELETED(parent))
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
		trigger_allergy()
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
		if(locate(/obj/structure/flora) in things)
			trigger_allergy()
			return
		if(locate(/obj/effect/plant) in things)
			trigger_allergy()
			return
		for(var/obj/item/toy/bouquet/flowers in things)
			if(istype(flowers, /obj/item/toy/bouquet/fake)) //Plastic doesn't trigger pollen.
				continue
			trigger_allergy()
			return
		for(var/obj/machinery/portable_atmospherics/hydroponics/irritant_tray in things)
			if(!irritant_tray.dead && !isnull(irritant_tray.seed))
				trigger_allergy()
				return

/datum/component/pollen_disability/proc/trigger_allergy()
	to_chat(owner, span_danger("[pick("The air feels itchy!","Your face feels uncomfortable!","Your body tingles!")]"))
	owner.add_modifier(/datum/modifier/allergic_flare, 3 SECONDS)

/datum/component/pollen_disability/Destroy(force = FALSE)
	UnregisterSignal(owner, COMSIG_HANDLE_DISABILITIES)
	owner = null
	. = ..()
