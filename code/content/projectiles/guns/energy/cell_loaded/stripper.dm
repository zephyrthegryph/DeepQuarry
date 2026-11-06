/obj/item/projectile/bullet/stripper
	icon_state = "magicm"
	nodamage = 1
	agony = 5

CAPABILITIES(/obj/item/projectile/bullet/stripper)
	configure(item_combat(embed_chance = 0, injury_kind = INJURY_BLUNT))
	configure(item_combat(sharp = FALSE))

/obj/item/projectile/bullet/stripper/on_hit(atom/stripped)
	if(ishuman(stripped))
		var/mob/living/carbon/human/H = stripped
		if(H.get_equipped_item(SLOT_ID_SUIT))
			H.unEquip(H.get_equipped_item(SLOT_ID_SUIT))
		if(H.get_equipped_item(SLOT_ID_UNIFORM))
			H.unEquip(H.get_equipped_item(SLOT_ID_UNIFORM))
		if(H.get_equipped_item(SLOT_ID_BACK))
			H.unEquip(H.get_equipped_item(SLOT_ID_BACK))
		if(H.get_equipped_item(SLOT_ID_SHOES))
			H.unEquip(H.get_equipped_item(SLOT_ID_SHOES))
		if(H.get_equipped_item(SLOT_ID_GLOVES))
			H.unEquip(H.get_equipped_item(SLOT_ID_GLOVES))
		//Hats can stay! Most other things fall off with removing these.
	..()
