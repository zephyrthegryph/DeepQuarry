/obj/item/dice
	name = "d6"
	desc = "A dice with six sides."
	icon = 'icons/obj/dice.dmi'
	icon_state = "d66"
	w_class = ITEMSIZE_TINY
	var/sides = 6
	var/result = 6
	var/loaded = null //Set to an integer when the die is loaded
	var/cheater = FALSE //TRUE if the die is able to be weighted by hand
	var/tamper_proof = FALSE //Set to TRUE if the die needs to be unable to be weighted, such as for events
	attack_verb = list("diced")

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/dice/proc/roll_icon_state(datum/roller/R)
	return "[name][R.number(1, sides)]"

/// Old attackby.
/obj/item/dice/proc/interaction_item(datum/act/op/A)
	if(istype(A.held, /obj/item/flame/lighter))
		weight_die(A.actor)
	return OP_PASS

/obj/item/dice/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	weight_die(user)
	return OP_OK

/obj/item/dice/proc/weight_die(mob/user)
	return dice_weight_stage(user)

/obj/item/dice/proc/dice_weight_stage(mob/user, dice_answer, dice_answer_ready = FALSE)
	if(cheater)
		to_chat(user, span_warning("Wait, this [name] is already weighted!"))
	else if(tamper_proof)
		to_chat(user, span_warning("This [name] is proofed against tampering!"))
	else
		if(!dice_answer_ready)
			open_request(src, /datum/prompt/number/dice_configuration, PROC_REF(dice_weight_answered), answerer = user, dice_operator = user, question = "What should the [name] be weighted towards? You can't undo this later, only change the number!", title = "Set the desired result", default = 1, dice_ui_max = 6)
			return
		var/to_weight = dice_answer
		if(isnull(to_weight))
			return
		if(isnull(to_weight) || (to_weight < 1) || (to_weight > sides))
			return FALSE
		else
			to_chat(user, "You partially melt the [name], weighting it towards [to_weight]...")
			desc = "[initial(desc)] It looks a little misshapen, somehow..."
			loaded = to_weight
	return TRUE

/// Old click_alt.
/obj/item/dice/proc/interaction_alt(datum/act/op/A)
	dice_cheat_stage(A.actor, A.held)
	return OP_OK

/obj/item/dice/proc/dice_cheat_stage(mob/user, obj/item/held, dice_answer, dice_answer_ready = FALSE)
	if(cheater)
		if(!loaded)
			if(!dice_answer_ready)
				open_request(src, /datum/prompt/number/dice_configuration, PROC_REF(dice_cheat_answered), answerer = user, dice_operator = user, dice_held = held, question = "What should the [name] be weighted towards?", title = "Set the desired result", default = 1, dice_ui_max = sides)
				return TRUE
			var/to_weight = dice_answer
			if(isnull(to_weight))
				return TRUE
			if(isnull(to_weight) || (to_weight < 1) || (to_weight > sides) ) //You must input a number higher than 0 and no greater than the number of sides
				return TRUE
			else
				to_chat(user, "You sneakily set the [name] to land on [to_weight]...")
				loaded = to_weight
		else
			to_chat(user, "You set the [name] to roll randomly again.")
			loaded = null
	return TRUE

/obj/item/dice/loaded
	cheater = TRUE

/obj/item/dice/d4
	name = "d4"
	desc = "A dice with four sides."
	icon_state = "d44"
	sides = 4
	result = 4

/obj/item/dice/d8
	name = "d8"
	desc = "A dice with eight sides."
	icon_state = "d88"
	sides = 8
	result = 8

/obj/item/dice/d10
	name = "d10"
	desc = "A dice with ten sides."
	icon_state = "d1010"
	sides = 10
	result = 10

/obj/item/dice/d12
	name = "d12"
	desc = "A dice with twelve sides."
	icon_state = "d1212"
	sides = 12
	result = 12

/obj/item/dice/d20
	name = "d20"
	desc = "A dice with twenty sides."
	icon_state = "d2020"
	sides = 20
	result = 20

/obj/item/dice/d100
	name = "d100"
	desc = "A dice with ten sides. This one is for the tens digit."
	icon_state = "d10010"
	sides = 10
	result = 10

CAPABILITIES(/obj/item/dice)
	op("roll", in_hand(), label("Roll die"), then(PROC_REF(dice_roll_requested)))
	op("interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_item)))
	op("interaction_alt", hand(), ungated(), gesture(GESTURE_ALT), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_alt)))
	op("dice_verb_set_face", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Set Face"), then(PROC_REF(dice_verb_set_face)))
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))
	op("use_welder", tool(TOOL_WELDER), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))

/obj/item/dice/proc/dice_roll_requested(datum/act/op/A)
	rollDice(A.actor, 0)
	return OP_OK

/obj/item/dice/proc/rollDice(mob/user, silent = FALSE)
	result = rand(1, sides)
	if(loaded)
		if(cheater)
			if(prob(90))
				result = loaded
		else if(prob(75)) //makeshift weighted dice don't always work
			result = loaded
	icon_state = "[name][result]"
	if(isliving(user)) //An omen can override dice rolls!
		var/mob/living/roller = user
		var/override = roller.omen_roll_override(src, silent, result)
		if(override)
			result = override

	if(!silent)
		var/comment = ""
		if(sides == 20 && result == 20)
			comment = "Nat 20!"
		else if(sides == 20 && result == 1)
			comment = "Ouch, bad luck."

		act_message(user, src, MSG_SELF(span_notice("You throw %T%. It lands on a [result]. [comment]")), \
			MSG_OTHERS(span_notice("%U% has thrown %T%. It lands on [result]. [comment]")), \
			MSG_BLIND(span_notice("You hear %T% landing on a [result]. [comment]")))

/// Old Set Face verb: Turn the dice to a specific face.
/obj/item/dice/proc/dice_verb_set_face(datum/act/op/A)
	var/mob/user = A.actor
	if(!iscarbon(user))
		return OP_OK

	set_dice(user)
	return OP_OK

/obj/item/dice/proc/set_dice(mob/user)
	return dice_face_stage(user)

/obj/item/dice/proc/dice_face_stage(mob/user, dice_answer, dice_answer_ready = FALSE)
	if(user.stat || !Adjacent(user))
		return
	if(!dice_answer_ready)
		open_request(src, /datum/prompt/number/dice_configuration, PROC_REF(dice_face_answered), answerer = user, dice_operator = user, question = "What face should \the [src] be turned to?", title = "Set die face", default = 1, dice_ui_max = sides)
		return
	var/to_value = dice_answer
	if(isnull(to_value))
		return
	if(!to_value)
		return

	result = to_value
	icon_state = "[name][result]"
	act_message(user, src, others = span_notice("%U% turned %T% to the face reading [result] manually."))

/obj/item/dice/item_ctrl_click(mob/user)
	set_dice(user)


/*
 * Dice packs
 */

/obj/item/storage/pill_bottle/dice	//7d6
	name = "bag of dice"
	desc = "It's a small bag with dice inside."
	icon = 'icons/obj/dice.dmi'
	icon_state = "dicebag"
	drop_sound = SFX_ITEMS_DROP_HAT
	pickup_sound = SFX_ITEMS_PICKUP_HAT

/obj/item/storage/pill_bottle/dice
	starts_with = list(
		/obj/item/dice = 7,
	)

/obj/item/storage/pill_bottle/dice_nerd	//DnD dice
	name = "bag of gaming dice"
	desc = "It's a small bag with gaming dice inside."
	icon = 'icons/obj/dice.dmi'
	icon_state = "magicdicebag"
	drop_sound = SFX_ITEMS_DROP_HAT
	pickup_sound = SFX_ITEMS_PICKUP_HAT

/obj/item/storage/pill_bottle/dice_nerd
	starts_with = list(
		/obj/item/dice/d4 = 1,
		/obj/item/dice = 1,
		/obj/item/dice/d8 = 1,
		/obj/item/dice/d10 = 1,
		/obj/item/dice/d12 = 1,
		/obj/item/dice/d20 = 1,
		/obj/item/dice/d100 = 1,
	)

/*
 *Liar's Dice cup
 */

/obj/item/storage/dicecup
	name = "dice cup"
	desc = "A cup used to conceal and hold dice."
	icon = 'icons/obj/dice.dmi'
	icon_state = "dicecup"
	w_class = ITEMSIZE_SMALL
	storage_slots = 5
	special_handling = TRUE


CAPABILITIES(/obj/item/storage/dicecup)
	configure(storage(accepts = list(/obj/item/dice)))
	op("interaction_shake", in_hand(), label("Shake"), then(PROC_REF(interaction_shake)))
	op("dicecup_verb_peek", menu(), label("Peek at Dice"), needs(carried()), then(PROC_REF(dicecup_verb_peek)))
	op("dicecup_verb_reveal", menu(), label("Reveal Dice"), needs(carried()), then(PROC_REF(dicecup_verb_reveal)))

/// Old attack_self: shake the cup.
/obj/item/storage/dicecup/proc/interaction_shake(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, MSG_SELF(span_notice("You shake %T%.")), \
		MSG_OTHERS(span_notice("%U% shakes %T%.")), \
		MSG_BLIND(span_notice("You hear dice rolling.")))
	rollCup(user)

/obj/item/storage/dicecup/proc/rollCup(mob/user)
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/dice/I in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		var/obj/item/dice/D = I
		D.rollDice(user, 1)

/obj/item/storage/dicecup/proc/revealDice(mob/viewer)
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/dice/I in contents_of(src)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		var/obj/item/dice/D = I
		to_chat(viewer, "The [D.name] shows a [D.result].")

/// Old Peek at Dice verb: Peek at the dice under your cup.
/obj/item/storage/dicecup/proc/dicecup_verb_peek(datum/act/op/A)
	var/mob/user = A.actor
	revealDice(user)

/// Old Reveal Dice verb: Reveal the dice hidden under your cup.
/obj/item/storage/dicecup/proc/dicecup_verb_reveal(datum/act/op/A)
	var/mob/user = A.actor
	for(var/mob/living/player in viewers(3, user))
		to_chat(player, "[user] reveals their dice.")
		revealDice(player)


/obj/item/storage/dicecup/loaded
	starts_with = list(
		/obj/item/dice = 5,
	)

/obj/item/dice/d20/cursed
	name = "d20"
	desc = "A dice with twenty sides."
	icon_state = "d2020"
	sides = 20
	result = 20

	///If the dice will apply the major version of unlucky or not.
	var/evil = TRUE


/obj/item/dice/d20/cursed/rollDice(mob/user, silent = FALSE)
	..()
	if(result == 1)
		to_chat(user, span_cult("You feel extraordinarily unlucky..."))
		var/mob/living/cursed_user = user
		if(!istype(cursed_user))
			return FALSE
		if(evil)
			cursed_user.add_omen(incidents_left = 1, luck_mod = 1, damage_mod = 1, evil = TRUE, safe_disposals = FALSE, vorish = TRUE)

		else
			cursed_user.add_omen(incidents_left = 1, luck_mod = 0.3, damage_mod = 1, evil = FALSE, safe_disposals = FALSE, vorish = TRUE)

/obj/item/dice/proc/dice_weight_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = dice_weight_apply(A)
	SStgui.update_uis(src)

/obj/item/dice/proc/dice_weight_apply(datum/act/request/A)
	var/datum/prompt/number/dice_configuration/ask = A.answer
	return dice_weight_stage(ask.dice_operator, ask.value, TRUE)

/obj/item/dice/proc/dice_cheat_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = dice_cheat_apply(A)
	SStgui.update_uis(src)

/obj/item/dice/proc/dice_cheat_apply(datum/act/request/A)
	var/datum/prompt/number/dice_configuration/ask = A.answer
	return dice_cheat_stage(ask.dice_operator, ask.dice_held, ask.value, TRUE)

/obj/item/dice/proc/dice_face_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = dice_face_apply(A)
	SStgui.update_uis(src)

/obj/item/dice/proc/dice_face_apply(datum/act/request/A)
	var/datum/prompt/number/dice_configuration/ask = A.answer
	return dice_face_stage(ask.dice_operator, ask.value, TRUE)

/datum/prompt/number/dice_configuration
	timeout = 0
	min_value = null
	max_value = null
	step = null
	var/dice_ui_max = 6
	var/mob/dice_operator
	var/obj/item/dice_held
	var/dice_operator_expected = FALSE
	var/dice_held_expected = FALSE

CAPABILITIES(/datum/prompt/number/dice_configuration)
	ref_one(nameof(dice_operator), /mob)
	ref_one(nameof(dice_held), /obj/item)

/datum/prompt/number/dice_configuration/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = dice_operator
	var/obj/item/captured_held = dice_held
	dice_operator_expected = !isnull(captured_operator)
	dice_held_expected = !isnull(captured_held)
	rel_clear(src, nameof(dice_operator))
	rel_clear(src, nameof(dice_held))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(dice_operator), captured_operator)
	if(captured_held && !QDELETED(captured_held))
		rel_set(src, nameof(dice_held), captured_held)

/datum/prompt/number/dice_configuration/recheck_extra()
	if((dice_operator_expected && QDELETED(dice_operator)) || (dice_held_expected && QDELETED(dice_held)))
		return "gone"

/datum/prompt/number/dice_configuration/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, dice_ui_max, 1, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box
