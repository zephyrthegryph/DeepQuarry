//TESHARI FACE MASK //Defning all the procs in one go
/obj/item/clothing/mask/synthfacemask
	name = "Synth Face"
	desc = "A round dark muzzle made of LEDs."
	flags = PHORONGUARD //Since it cant easily be removed...
	item_flags = AIRTIGHT | FLEXIBLEMATERIAL | BLOCK_GAS_SMOKE_EFFECT //This should make it properly work as a mask... and allow you to eat stuff through it!
	icon = 'icons/mob/species/teshari/synth_facemask.dmi'
	icon_override = 'icons/mob/species/teshari/synth_facemask.dmi'
	icon_state = "synth_facemask"
	var/lstat
	var/visor_state = "Neutral" //Separating this from lstat so that it could potentially be used for an override system or something
	var/maskmaster_handle
	resistance_flags = FIRE_PROOF | ACID_PROOF | INDESTRUCTIBLE | BOMB_PROOF |FREEZE_PROOF

/obj/item/clothing/mask/synthfacemask/equipped()
	..()
	var/mob/living/carbon/human/H = loc
	if(istype(H) && H.get_equipped_item(SLOT_ID_MASK) == src)
		canremove = FALSE
		maskmaster_handle = om_handle(H)
		om_task_periodic(src, PERIODIC_SECOND)

/obj/item/clothing/mask/synthfacemask/dropped(mob/user, equipping, slot)
	canremove = TRUE
	maskmaster_handle = null
	om_task_periodic_stop(src)
	..()

TYPE_TABLE(/obj/item/clothing/mask/synthfacemask, equip_spec, dq_spec_join(..(), list(REQ_ON(PRED_TARGET, /obj/item/clothing/mask/synthfacemask/proc/robotic_head, "you must have a compatible robotic head to install this upgrade"))))

/obj/item/clothing/mask/synthfacemask/proc/robotic_head(mob/living/carbon/human/H)
	if(!istype(H))
		return FALSE
	var/obj/item/organ/external/E = H.organs_by_name[BP_HEAD]
	return istype(E) && (E.is_robotic())

DECLARE_APPEARANCE_PROC(/obj/item/clothing/mask/synthfacemask, PROC_REF(appearance_overlays), list())
/obj/item/clothing/mask/synthfacemask/appearance_overlays()
	. = list()
	var/mob/living/carbon/human/H = loc
	switch(visor_state)
		if (DEAD)
			icon_state = "synth_facemask_dead"
		else
			icon_state = "synth_facemask"
	if(istype(H)) H.update_inv_wear_mask()

/obj/item/clothing/mask/synthfacemask/periodic_step()
	if(maskmaster() && lstat != maskmaster().stat)
		lstat = maskmaster().stat
		visor_state = "Neutral" //This does nothing at the moment, but it's there incase anyone wants to add more states.
		//Maybe a verb that sets an emote override here
		if(lstat == DEAD)
			visor_state = DEAD
		update_icon()

//LOADOUT ITEM
/datum/gear/mask/synthface/
	display_name = "Synth Facemask (Teshari)"
	path = /obj/item/clothing/mask/synthfacemask
	sort_category = "Xenowear"
	whitelisted = SPECIES_TESHARI
	cost = 1

/datum/gear/mask/synthface/New()
	..()
	LAZYADD(gear_tweaks, GLOB.gear_tweak_free_color_choice)

/// LC-refs: the maskmaster this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/clothing/mask/synthfacemask/proc/maskmaster() as /mob/living/carbon
	return om_resolve(maskmaster_handle)
