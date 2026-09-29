/obj/item/towel
	name = "towel"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "towel"
	slot_flags = SLOT_HEAD | SLOT_BELT | SLOT_OCLOTHING
	force = 3.0
	w_class = ITEMSIZE_NORMAL
	attack_verb = list("whipped")
	hitsound = 'sound/weapons/towelwhip.ogg'
	desc = "A soft cotton towel."
	drop_sound = 'sound/items/drop/cloth.ogg'
	pickup_sound = 'sound/items/pickup/cloth.ogg'

/obj/item/towel/equipped(M, slot)
	..()
	switch(slot)
		if(SLOT_ID_HEAD)
			sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/head/mob_teshari.dmi')
		if(SLOT_ID_SUIT)
			sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/suit/mob_teshari.dmi')
		if(SLOT_ID_BELT)
			sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/belt/mob_teshari.dmi')

DECLARE_INTERACTIONS(/obj/item/towel, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/towel/proc/interaction_self(mob/living/user, obj/item/held, datum/interaction/interaction)
	act_message(user, src, others = span_notice("%U% uses %T% to towel themselves off."))
	playsound(src, 'sound/weapons/towelwipe.ogg', 25, 1)
	if(user.fire_stacks > 0)
		user.adjust_fire_stacks(-1.5)
	return TRUE

/obj/item/towel/random/Initialize(mapload)
	. = ..()
	color = get_random_colour()
