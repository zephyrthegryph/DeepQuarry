//TESHARI FACE MASK //Defning all the procs in one go
/obj/item/clothing/mask/synthfacemask
	name = "Synth Face"
	desc = "A round dark muzzle made of LEDs."
	flags = PHORONGUARD //Since it cant easily be removed...
	icon = 'icons/mob/species/teshari/synth_facemask.dmi'
	icon_override = 'icons/mob/species/teshari/synth_facemask.dmi'
	icon_state = "synth_facemask"
	var/lstat
	var/visor_state = "Neutral" //Separating this from lstat so that it could potentially be used for an override system or something
	resistance_flags = FIRE_PROOF | ACID_PROOF | INDESTRUCTIBLE | BOMB_PROOF |FREEZE_PROOF


/// The wearer it is installed on (a relation view); the visor follows their state while set.
/obj/item/clothing/mask/synthfacemask/var/mob/living/carbon/maskmaster

CAPABILITIES(/obj/item/clothing/mask/synthfacemask)
	acceptance("equip", req_acceptance_robotic_head(), mode = ACCEPTANCE_APPEND)
	configure(item_worn(flags = AIRTIGHT | FLEXIBLEMATERIAL | BLOCK_GAS_SMOKE_EFFECT))
	ref_one(nameof(maskmaster))
	every(1 SECOND, then(PROC_REF(synthfacemask_step)), when = nameof(maskmaster))

/obj/item/clothing/mask/synthfacemask/equipped()
	..()
	var/mob/living/carbon/human/H = loc
	if(istype(H) && H.get_equipped_item(SLOT_ID_MASK) == src)
		set_canremove(FALSE)
		rel_set(src, nameof(maskmaster), H)

/obj/item/clothing/mask/synthfacemask/dropped(mob/user, equipping, slot)
	set_canremove(TRUE)
	rel_clear(src, nameof(maskmaster))
	..()



/obj/item/clothing/mask/synthfacemask/proc/robotic_head(datum/act/op/A)
	var/mob/living/carbon/human/H = A.wearer
	if(!istype(H))
		return "you must have a compatible robotic head to install this upgrade"
	var/obj/item/organ/external/E = H.organs_by_name[BP_HEAD]
	return istype(E) && E.is_robotic() ? null : "you must have a compatible robotic head to install this upgrade"

/obj/item/clothing/mask/synthfacemask/draw(datum/look/look)
	..()
	switch(visor_state)
		if (DEAD)
			look.state("synth_facemask_dead")
		else
			look.state("synth_facemask")

/obj/item/clothing/mask/synthfacemask/proc/synthfacemask_step(datum/act/timer/A)
	if(maskmaster() && lstat != maskmaster().stat)
		lstat = maskmaster().stat
		set_visor_state("Neutral") //This does nothing at the moment, but it's there incase anyone wants to add more states.
		//Maybe a verb that sets an emote override here
		if(lstat == DEAD)
			set_visor_state(DEAD)

//LOADOUT ITEM
/datum/gear/mask/synthface/
	display_name = "Synth Facemask (Teshari)"
	path = /obj/item/clothing/mask/synthfacemask
	sort_category = "Xenowear"
	whitelisted = SPECIES_TESHARI
	cost = 1

/datum/gear/mask/synthface/New()
	..()
	rel_add(src, nameof(gear_tweaks), new /datum/gear_tweak/color)

/// the maskmaster this refers to (a relation view: null once it is deleted).
/obj/item/clothing/mask/synthfacemask/proc/maskmaster() as /mob/living/carbon
	return maskmaster

/proc/req_acceptance_robotic_head()
	return part_make(/datum/entry/part/req/acceptance_leaf/robotic_head, list())


/datum/entry/part/req/acceptance_leaf/robotic_head/acceptance_reason(datum/act/op/A)
	var/obj/item/clothing/mask/synthfacemask/I = A.target
	return I.robotic_head(A)


/datum/entry/part/req/acceptance_leaf/robotic_head/read_keys(datum/act/op/A)
	. = list()
	var/mob/living/carbon/human/H = A.wearer
	if(!istype(H))
		return
	. += list(list(H, SLOT_OCCUPANCY_KEY), list(H, nameof(H.organs)))
	// organs_by_name is a derived external-part cache. Track actual tree-slot
	// owners and membership rather than introducing a second state map.
	for(var/obj/item/organ/external/E as anything in H.organs)
		. += list(list(E, SLOT_OCCUPANCY_KEY), list(E, nameof(E.robotic)), list(E, nameof(E.organ_tag)))
