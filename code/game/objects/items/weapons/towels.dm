/obj/item/towel
	name = "towel"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "towel"
	slot_flags = SLOT_HEAD | SLOT_BELT | SLOT_OCLOTHING
	force = 3.0
	w_class = ITEMSIZE_NORMAL
	attack_verb = list("whipped")
	hitsound = SFX_WEAPONS_TOWELWHIP
	desc = "A soft cotton towel."
	drop_sound = SFX_ITEMS_DROP_CLOTH
	pickup_sound = SFX_ITEMS_PICKUP_CLOTH

/obj/item/towel/equipped(M, slot)
	..()
	switch(slot)
		if(SLOT_ID_HEAD)
			sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/head/mob_teshari.dmi')
		if(SLOT_ID_SUIT)
			sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/suit/mob_teshari.dmi')
		if(SLOT_ID_BELT)
			sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/belt/mob_teshari.dmi')

CAPABILITIES(/obj/item/towel)
	op("wipe", in_hand(), label("Towel yourself off"), then(PROC_REF(toweled_off)))

/// The towel keeps the same wiping effect on its actual actor.
/obj/item/towel/proc/toweled_off(datum/act/op/A)
	var/mob/living/user = A.actor
	act_message(user, src, others = span_notice("%U% uses %T% to towel themselves off."))
	play_sfx(src, SFX_WEAPONS_TOWELWIPE)
	if(user.fire_stacks > 0)
		user.adjust_fire_stacks(-1.5)
	return OP_OK

CAPABILITIES(/obj/item/towel/random)
	rolls(nameof(color), PROC_REF(roll_color))

/// Rolled before init (rolls()): any colour (get_random_colour()'s distribution).
/obj/item/towel/random/proc/roll_color(datum/roller/R)
	return R.hex_colour()

