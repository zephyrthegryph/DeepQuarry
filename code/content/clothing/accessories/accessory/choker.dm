//
// Collars and such like that
//

/obj/item/clothing/accessory/choker //A colorable, tagless choker
	name = "plain choker"
	desc = "A simple, plain choker. Or maybe it's a collar?"
	icon_state = "choker_cst"
	item_state = "choker_cst"
	overlay_state = "choker_cst"
	var/customized = 0
	var/icon_previous_override

CAPABILITIES(/obj/item/clothing/accessory/choker)
	configure(item_worn(slots = SLOT_TIE | SLOT_OCLOTHING))

//Forces different sprite sheet on equip
/obj/item/clothing/accessory/choker/on_materialize()
	icon_previous_override = icon_override
	. = ..()

/obj/item/clothing/accessory/choker/equipped() //Solution for race-specific sprites for an accessory which is also a suit. Suit icons break if you don't use icon override which then also overrides race-specific sprites.
	..()
	setUniqueSpeciesSprite()

/obj/item/clothing/accessory/choker/proc/setUniqueSpeciesSprite()
	var/mob/living/carbon/human/H = loc
	if(!istype(H) && istype(has_suit(), /obj/item/clothing) && ishuman(has_suit().loc))
		H = has_suit().loc
	if(sprite_sheets && istype(H) && H.species.get_bodytype(H) && (H.species.get_bodytype(H) in sprite_sheets))
		set_icon_override(sprite_sheets[H.species.get_bodytype(H)])

/obj/item/clothing/accessory/choker/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	rel_set(src, nameof(has_suit), S)
	setUniqueSpeciesSprite()
	..(S, user)

/obj/item/clothing/accessory/choker/dropped(mob/user, equipping, slot)
	..()
	set_icon_override(icon_previous_override)
