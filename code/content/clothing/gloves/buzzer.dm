// Buzzer Ring - Traitor, Merc.
/obj/item/clothing/gloves/ring/buzzer
	name = "ring"
	desc = "A plain metal band."
	icon_state = "material"
	var/battery_type = /obj/item/cell/device/weapon/recharge
	var/obj/item/cell/battery = null
// The battery is built in (nothing removes it): it goes with the ring, not onto the floor.

/obj/item/clothing/gloves/ring/buzzer/get_cell()
	return battery

CAPABILITIES(/obj/item/clothing/gloves/ring/buzzer)
	configure(atom_rules(description_antag = "This morphium-alloy ring continually generates an electric field, capable of electrocuting a target while not injuring the wearer.\
	The device is also capable of 'frankenstein'-ing a corpse, long after normal technology would be able to save them. The body will still be tied to the\
	normal damage limits for survival, however, so care must be taken."))
	owns_one(nameof(battery), starts = nameof(battery_type))

/obj/item/clothing/gloves/ring/buzzer/Touch(atom/A, proximity, stance = I_HURT, mob/user)
	if(proximity && istype(user, /mob/living/carbon/human))
		return zap(user, A, proximity, stance)
	return 0

/obj/item/clothing/gloves/ring/buzzer/proc/zap(mob/living/carbon/human/user, atom/movable/target, proximity, stance = I_HURT)
	. = FALSE
	if(stance == I_HURT && battery.percent() >= 50)
		if(isliving(target))
			var/mob/living/L = target

			if(ishuman(L) && battery.percent() >= 90)	// Silent text-wise, for maximum potential for gimmicks.
				var/mob/living/carbon/human/H = L

				if(H.stat == DEAD)
					. = TRUE

					do_defib(H)

			to_chat(L, span_warning("You feel a powerful shock!"))
			if(!.)
				play_sfx(L, SFX_EFFECTS_SPARKS7)
				L.electrocute_act(battery.percent() * 0.25, src)
				battery.emp_act(2)
			return .

	return 0

/obj/item/clothing/gloves/ring/buzzer/proc/do_defib(mob/living/carbon/human/H = null)
	if(!istype(H))
		return 0

	if(H.return_from_death("buzzer ring", src, REVIVE_UNCONSCIOUS) != TRUE)
		return 0

	H.emote("gasp")
	H.status_at_least(STAT_WEAKENED, rand(10,25))

	battery.emp_act(1)
