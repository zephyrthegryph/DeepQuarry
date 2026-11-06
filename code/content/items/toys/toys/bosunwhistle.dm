/*
 * Bosun's whistle
 */
/obj/item/toy/bosunwhistle
	name = "bosun's whistle"
	desc = "A genuine Admiral Krush Bosun's Whistle, for the aspiring ship's captain! Suitable for ages 8 and up, do not swallow."
	icon = 'icons/obj/toy.dmi'
	icon_state = "bosunwhistle"
	var/cooldown = 0
	w_class = ITEMSIZE_TINY

CAPABILITIES(/obj/item/toy/bosunwhistle)
	configure(item_worn(slots = SLOT_EARS | SLOT_HOLSTER))
	configure(item_sounds(drop = SFX_ITEMS_DROP_CARD))
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/toy/bosunwhistle/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(COOLDOWN_FINISHED(src, cooldown))
		to_chat(user, span_notice("You blow on [src], creating an ear-splitting noise!"))
		play_sfx(src, SFX_MISC_BOATSWAIN)
		COOLDOWN_START(src, cooldown, 3.5 SECONDS)
	return TRUE
