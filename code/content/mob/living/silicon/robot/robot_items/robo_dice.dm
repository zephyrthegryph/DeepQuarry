// Simple that lets a cyborg roll a collection of die.
/obj/item/robo_dice
	name = "random number generator"
	desc = "A robot device that allows a synthetic entity to, finally, make random numbers. The future is here."
	icon = 'icons/obj/integrated_electronics/electronic_setups.dmi'
	icon_state = "setup_device_box"

CAPABILITIES(/obj/item/robo_dice)
	op("self", in_hand(),
		asks(/datum/prompt/choice, fields = list("choices" = computed(PROC_REF(dice_options)), "radial" = TRUE, "anchor" = computed(PROC_REF(dice_anchor)), "radius" = 70, "autopick_single_option" = TRUE, "timeout" = 0), step = "die"),
		asks(/datum/prompt/number, fields = list("ask_flags" = ASK_CARRIED | ASK_CAPABLE, "title" = "Custom Dice Roll", "question" = "Enter how many faces you want your virtual dice to have, (no more than 1000 sides):", "default" = 6, "max_value" = 1000, "min_value" = 0, "timeout" = 0), step = "custom", when = PROC_REF(die_is_custom)),
		then(PROC_REF(interaction_self)))

/// The dice radial rings the user.
/obj/item/robo_dice/proc/dice_anchor(datum/act/op/A)
	return A.actor

/// A custom die asks how many faces it has.
/obj/item/robo_dice/proc/die_is_custom(datum/act/op/A)
	return A.step_value("die") == "roll a custom die"

/// The dice the radial offers.
/obj/item/robo_dice/proc/dice_options(datum/act/op/A)
	var/DI = 'icons/obj/dice.dmi'
	var/options = list(
		"roll a custom die"	= image(icon = 'icons/obj/integrated_electronics/electronic_setups.dmi', icon_state = "setup_device_box"),
		"roll d4"			= image(icon = DI, icon_state = "d44"),
		"roll d6"			= image(icon = DI, icon_state = "d66"),
		"roll d8"			= image(icon = DI, icon_state = "d88"),
		"roll d10"			= image(icon = DI, icon_state = "d1010"),
		"roll d12"			= image(icon = DI, icon_state = "d1212"),
		"roll d20"			= image(icon = DI, icon_state = "d2020"),
		"roll d100"			= image(icon = DI, icon_state = "d10010"),
	)
	return options

/// Old attack_self: the die the radial was answered with (a custom one with the faces asked).
/obj/item/robo_dice/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/die = A.step_value("die")
	if(isnull(die))
		return TRUE
	var/sides = 0
	switch(die)
		if("roll d4")
			sides = 4
		if("roll d6")
			sides = 6
		if("roll d8")
			sides = 8
		if("roll d10")
			sides = 10
		if("roll d12")
			sides = 12
		if("roll d20")
			sides = 20
		if("roll d100")
			sides = 100
		if("roll a custom die")
			var/faces = A.step_value("custom")
			if(isnull(faces))
				return TRUE
			sides = faces
	roll_die(user, sides)
	return TRUE

/obj/item/robo_dice/proc/roll_die(mob/user, sides)
	if(sides <= 0)
		return
	var/result = rand(1, sides)
	act_message(user, null, MSG_SELF(span_notice("You roll a virtual [sides]-sided die. The result is [result].")), \
		MSG_OTHERS(span_notice("%U% rolls a virtual [sides]-sided die. The result is [result].")), \
		MSG_BLIND(span_notice("You hear synthesized audio of clattering plastic with a soft ping.")))
	user.balloon_alert_visible("rolled: [result]", blind_message = "*clatter, ping!*")
	play_sfx(user, SFX_EFFECTS_DICEROLL_ROBOTIC)
