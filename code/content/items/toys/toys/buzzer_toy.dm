/*
 * Hand buzzer
 */
/obj/item/clothing/gloves/ring/buzzer/toy
	name = "steel ring"
	desc = "Torus shaped finger decoration. It has a small piece of metal on the palm-side."
	icon_state = "seal-signet"

CAPABILITIES(/obj/item/clothing/gloves/ring/buzzer/toy)
	configure(item_sounds(drop = SFX_ITEMS_DROP_RING))

/obj/item/clothing/gloves/ring/buzzer/toy/Touch(atom/A, proximity, stance = I_HURT, mob/user)
	if(proximity && istype(user, /mob/living/carbon/human))

		return zap(user, A, proximity, stance)
	return 0

/obj/item/clothing/gloves/ring/buzzer/toy/zap(mob/living/carbon/human/user, atom/movable/target, proximity, stance = I_HURT)
	. = FALSE
	if(stance == I_HELP && battery.percent() >= 50)
		if(isliving(target))
			var/mob/living/L = target

			to_chat(L, span_warning("You feel a powerful shock!"))
			if(!.)
				play_sfx(L, SFX_EFFECTS_SPARKS7)
				L.electrocute_act(battery.percent() * 0, src)
			return .

	return 0
