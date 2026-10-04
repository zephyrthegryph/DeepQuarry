/obj/item/stack/telecrystal
	name = "telecrystal"
	desc = "It seems to be pulsing with suspiciously enticing energies."
	description_antag = "Telecrystals can be activated by utilizing them on devices with an actively running uplink. They will not activate on unactivated uplinks."
	singular_name = "telecrystal"
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "telecrystal"
	w_class = ITEMSIZE_TINY
	max_amount = 240
	force = 1 //Needs a token force to ensure you can attack because for some reason you can't attack with 0 force things

/obj/item/stack/telecrystal/apply_hit_effect(mob/living/target, mob/living/user, hit_zone)
	if(amount >= 5)
		act_message(user, target, others = span_warning("%T% has been transported with \the [src] by %U%."))
		safe_blink(target, 14)
		use(5)
	else
		to_chat(user, span_warning("There are not enough telecrystals to do that."))

CAPABILITIES(/obj/item/stack/telecrystal)
	without("ui_open")
	op("redeem", in_hand(), then(PROC_REF(redeemed)))

/// Using the crystals in the hand adds them to your balance.
/obj/item/stack/telecrystal/proc/redeemed(datum/act/op/A)
	var/mob/user = A.actor
	if(user.mind && user.mind.accept_tcrystals) //Checks to see if antag type allows for tcrystals
		to_chat(user, span_notice("You use \the [src], adding [src.amount] to your balance."))
		user.mind.tcrystals += amount
		use(amount)
	return OP_OK
