/obj/machinery/fitness
	name = "workout equipment"
	desc = "A utility often used to lose weight."
	icon = 'icons/obj/machines/fitness_machines_vr.dmi'
	anchored = TRUE
	use_power = USE_POWER_OFF
	idle_power_usage = 0
	active_power_usage = 0
	var/messages
	var/workout_sounds
	var/cooldown = 10
	var/weightloss_power = 1

// Ungated, as the old attack_hand overrides never called ..(): the machinery operability checks never applied.
EXTEND_INTERACTIONS(/obj/machinery/fitness, INTERACT_HAND_UNGATED("Work out", PROC_REF(fitness_workout_hand)))

/// Old attack_hand: work out, burning nutrition and weight.
/obj/machinery/fitness/proc/fitness_workout_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	if(user.nutrition < 70)
		to_chat(user, span_notice("You need more energy to workout with the [src]!"))

	else if(user.weight < 70)
		to_chat(user, span_notice("You're too skinny to risk losing any more weight!"))

	else //If they have enough nutrition and body weight, they can exercise.
		user.setClickCooldown(cooldown)
		user.adjust_nutrition(-10 * weightloss_power)
		user.weight -= 0.25 * weightloss_power * (0.01 * user.weight_loss)
		flick("[icon_state]2", src)
		var/message = pick(messages)
		to_chat(user, span_notice("[message]."))
		for(var/s in workout_sounds)
			playsound(src, s, 50, 1)

/obj/machinery/fitness/punching_bag
	name = "punching bag"
	desc = "A bag often used to relieve stress and burn fat."
	icon_state = "punchingbag"
	anchored = FALSE
	density = TRUE
	workout_sounds = list(
		"punch")
	messages = list(
		"You slam your fist into the punching bag",
			"You jab the punching bag with your elbow")

/obj/machinery/fitness/punching_bag/clown
	name = "clown punching bag"
	desc = "A bag often used to releive stress and burn fat. It has a clown on the front of it."
	icon_state = "bopbag"
	workout_sounds = list(
		"punch",
		"clownstep",
		"sound/items/bikehorn.ogg")
	messages = list(
		"You slam your fist into the punching bag",
			"You jab the punching bag with your elbow",
			"You hammer the clown right in it's face with your fist",
			"A honk emits from the punching bag as you hit it")

/obj/machinery/fitness/heavy/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	add_fingerprint(user)
	act_message(user, src, MSG_SELF(span_notice("You [anchored ? "un" : ""]secure %T%.")), \
		MSG_OTHERS(span_warning("%U% has [anchored ? "un" : ""]secured %T%.")))
	set_anchored(!anchored)
	playsound(src, tool.usesound, 50, TRUE)
	return OP_OK

CAPABILITIES(/obj/machinery/fitness/heavy)
	op("heavy_fitness_safety_hand", hand(), then(PROC_REF(heavy_fitness_safety_hand)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(wrench_used)))

/// Old attack_hand: safety checks; FALSE goes on to the workout.
/obj/machinery/fitness/heavy/proc/heavy_fitness_safety_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!anchored)
		to_chat(user, span_notice("For safety reasons, you are required to have this equipment wrenched down before using it!"))
		return TRUE

	else if(user.loc != loc)
		to_chat(user, span_notice("For safety reasons, you need to be sitting in the [src] for it to work!"))
		return TRUE

	return OP_DECLINE

/obj/machinery/fitness/heavy/lifter
	name = "fitness lifter"
	desc = "A specialized machine that can be used for an assortment of excercises involving moving some weight repeatedly. Often used with the goal of losing weight."
	icon_state = "fitnesslifter" //Sprites ripped from goon.
	messages = list("You lift some weights")
	weightloss_power = 2
	cooldown = 40

/obj/machinery/fitness/heavy/treadmill
	name = "treadmill"
	desc = "A treadmill for running on! Often used with the goal of losing weight."
	icon_state = "treadmill"
	messages = list("You run for a while")
	weightloss_power = 2
	cooldown = 40

/obj/machinery/scale
	name = "scale"
	icon = 'icons/obj/machines/fitness_machines_vr.dmi'
	icon_state = "scale"
	desc = "A scale used to measure ones weight relative to their size and species."
	anchored = TRUE // Set to 0 when we can construct or dismantle these.
	use_power = USE_POWER_OFF
	idle_power_usage = 0
	active_power_usage = 0

EXTEND_INTERACTIONS(/obj/machinery/scale, INTERACT_HAND_UNGATED("Weigh", PROC_REF(scale_weigh_hand)))

/// Old attack_hand: read out the weight of whoever stands on it.
/obj/machinery/scale/proc/scale_weigh_hand(mob/living/user, obj/item/held, datum/interaction/interaction)
	. = TRUE
	if(user.loc != loc)
		to_chat(user, span_notice("You need to be standing on top of the scale for it to work!"))
		return
	if(user.weight) //Just in case.
		var/kilograms = round(text2num(user.weight),4) / 2.20463
		act_message(src, user, others = span_notice("%U% displays a reading of [user.weight]lb / [kilograms]kg when %T% stands on it."))
