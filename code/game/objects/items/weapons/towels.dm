/obj/item/towel
	name = "towel"
	icon = 'icons/obj/weapons.dmi'
	icon_state = "towel"
	w_class = ITEMSIZE_NORMAL
	desc = "A soft cotton towel."

/obj/item/towel/equipped(M, slot)
	..()
	switch(slot)
		if(SLOT_ID_HEAD)
			set_sprite_sheets(list(SPECIES_TESHARI = 'icons/inventory/head/mob_teshari.dmi'))
		if(SLOT_ID_SUIT)
			set_sprite_sheets(list(SPECIES_TESHARI = 'icons/inventory/suit/mob_teshari.dmi'))
		if(SLOT_ID_BELT)
			set_sprite_sheets(list(SPECIES_TESHARI = 'icons/inventory/belt/mob_teshari.dmi'))

CAPABILITIES(/obj/item/towel)
	configure(item_worn(slots = SLOT_HEAD | SLOT_BELT | SLOT_OCLOTHING))
	configure(item_combat(force = 3.0, attack_verbs = list("whipped")))
	configure(item_sounds(hit = SFX_WEAPONS_TOWELWHIP, drop = SFX_ITEMS_DROP_CLOTH, pickup = SFX_ITEMS_PICKUP_CLOTH))
	op("wipe", in_hand(), label("Towel yourself off"), then(PROC_REF(toweled_off)))

/// The towel keeps the same wiping effect on its actual actor.
/obj/item/towel/proc/toweled_off(datum/act/op/A)
	var/mob/living/user = A.actor
	act_message(user, src, others = span_notice("%U% uses %T% to towel themselves off."))
	play_sfx(src, SFX_WEAPONS_TOWELWIPE)
	if(fire_stacks_of(user) > 0)
		user.adjust_fire_stacks(-1.5)
	return OP_OK

CAPABILITIES(/obj/item/towel/random)
	rolls(nameof(color), PROC_REF(roll_color))

/// Rolled before init (rolls()): any colour (get_random_colour()'s distribution).
/obj/item/towel/random/proc/roll_color(datum/roller/R)
	return R.hex_colour()

