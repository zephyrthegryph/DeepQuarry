/*
 * Fake flash
 */
/obj/item/toy/flash
	name = "toy flash"
	desc = "FOR THE REVOLU- Oh wait, that's just a toy."
	icon = 'icons/obj/device.dmi'
	icon_state = "flash"
	item_state = "flash"
	w_class = ITEMSIZE_TINY
	var/cooldown = 0
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand.dmi',
		)

/obj/item/toy/flash/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!cooldown)
		play_sfx(src.loc, SFX_WEAPONS_FLASH)
		flick("[initial(icon_state)]2", src)
		act_message(user, M, others = span_disarm("%U% doesn't blind %T% with the toy flash!"))
		cooldown = 1
		after(src, 5 SECONDS, PROC_REF(cooldownreset))
		return ..()

/obj/item/toy/flash/proc/cooldownreset()
	cooldown = 0
