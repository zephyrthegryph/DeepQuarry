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

/obj/item/dice/Initialize(mapload)
	. = ..()
	icon_state = "[name][rand(1,sides)]"

/// Old attackby.
/obj/item/dice/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/flame/lighter))
		weight_die(user)
	return INTERACTION_HANDLED_PASS

/obj/item/dice/welder_act(mob/user, obj/item/tool)
	weight_die(user)
	return ITEM_INTERACT_SUCCESS

/obj/item/dice/proc/weight_die(mob/user)
	if(cheater)
		to_chat(user, span_warning("Wait, this [name] is already weighted!"))
	else if(tamper_proof)
		to_chat(user, span_warning("This [name] is proofed against tampering!"))
	else
		var/to_weight = rerun_ask(user, "k33", PROC_REF(weight_die), args, /datum/om/prompt/number, message = "What should the [name] be weighted towards? You can't undo this later, only change the number!", title = "Set the desired result", default = 1, max = 6, min = 1)
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
/obj/item/dice/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(cheater)
		if(!loaded)
			var/to_weight = rerun_ask(user, "k46", PROC_REF(interaction_alt), args, /datum/om/prompt/number, message = "What should the [name] be weighted towards?", title = "Set the desired result", default = 1, max = sides, min = 1)
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
	description_info = "This is a loaded die! To change the number it's weighted to, alt-click it. To put it back to normal, alt-click it again."
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

DECLARE_INTERACTIONS(/obj/item/dice, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
	INTERACT_VERB("Set Face", PROC_REF(dice_verb_set_face)), \
)

/// Old attack_self.
/obj/item/dice/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	rollDice(user, 0)
	return TRUE

/obj/item/dice/proc/rollDice(mob/user, silent = FALSE)
	result = rand(1, sides)
	if(loaded)
		if(cheater)
			if(prob(90))
				result = loaded
		else if(prob(75)) //makeshift weighted dice don't always work
			result = loaded
	icon_state = "[name][result]"
	if(om_wants(user, /datum/om/event/before/dice_roll)) //We can override dice rolls!
		var/datum/om/event/before/dice_roll/roll = new(src, silent, result)
		om_emit(user, roll)
		if(roll.result_override)
			result = roll.result_override

	if(!silent)
		var/comment = ""
		if(sides == 20 && result == 20)
			comment = "Nat 20!"
		else if(sides == 20 && result == 1)
			comment = "Ouch, bad luck."

		user.visible_message(span_notice("[user] has thrown [src]. It lands on [result]. [comment]"), \
								span_notice("You throw [src]. It lands on a [result]. [comment]"), \
								span_notice("You hear [src] landing on a [result]. [comment]"))

/// Old Set Face verb: Turn the dice to a specific face.
/obj/item/dice/proc/dice_verb_set_face(mob/user, obj/item/held, datum/interaction/interaction)
	if(!iscarbon(user))
		return

	set_dice(user)

/obj/item/dice/proc/set_dice(mob/user)
	if(user.stat || !Adjacent(user))
		return
	var/to_value = rerun_ask(user, "k147", PROC_REF(set_dice), args, /datum/om/prompt/number, message = "What face should \the [src] be turned to?", title = "Set die face", default = 1, max = sides, min = 1)
	if(isnull(to_value))
		return
	if(!to_value)
		return

	result = to_value
	icon_state = "[name][result]"
	user.visible_message(span_notice("\The [user] turned \the [src] to the face reading [result] manually."))

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
	drop_sound = 'sound/items/drop/hat.ogg'
	pickup_sound = 'sound/items/pickup/hat.ogg'

/obj/item/storage/pill_bottle/dice/Initialize(mapload)
	. = ..()
	for(var/i = 1 to 7)
		new /obj/item/dice(src)

/obj/item/storage/pill_bottle/dice_nerd	//DnD dice
	name = "bag of gaming dice"
	desc = "It's a small bag with gaming dice inside."
	icon = 'icons/obj/dice.dmi'
	icon_state = "magicdicebag"
	drop_sound = 'sound/items/drop/hat.ogg'
	pickup_sound = 'sound/items/pickup/hat.ogg'

/obj/item/storage/pill_bottle/dice_nerd/Initialize(mapload)
	. = ..()
	new /obj/item/dice/d4(src)
	new /obj/item/dice(src)
	new /obj/item/dice/d8(src)
	new /obj/item/dice/d10(src)
	new /obj/item/dice/d12(src)
	new /obj/item/dice/d20(src)
	new /obj/item/dice/d100(src)

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

/obj/item/storage/dicecup/hold_constraint()
	var/list/holds = list(
		/obj/item/dice,
		)
	return list(HOLD_ONLY(holds), HOLD_MAX_SIZE(ITEMSIZE_SMALL))

EXTEND_INTERACTIONS(/obj/item/storage/dicecup, \
	INTERACT_USE("Shake", PROC_REF(interaction_shake)), \
	INTERACT_VERB("Peek at Dice", PROC_REF(dicecup_verb_peek), REQ_IN_INVENTORY), \
	INTERACT_VERB("Reveal Dice", PROC_REF(dicecup_verb_reveal), REQ_IN_INVENTORY), \
)

/// Old attack_self: after the storage's own self-use, shake the cup.
/obj/item/storage/dicecup/proc/interaction_shake(mob/user, obj/item/held, datum/interaction/interaction)
	if(interaction_self(user, held, interaction))
		return TRUE
	user.visible_message(span_notice("[user] shakes [src]."), \
							span_notice("You shake [src]."), \
							span_notice("You hear dice rolling."))
	rollCup(user)

/obj/item/storage/dicecup/proc/rollCup(mob/user)
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/dice/I in contents_of(src)) // ALLOW(latent): materialized above
		var/obj/item/dice/D = I
		D.rollDice(user, 1)

/obj/item/storage/dicecup/proc/revealDice(mob/viewer)
	latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/dice/I in contents_of(src)) // ALLOW(latent): materialized above
		var/obj/item/dice/D = I
		to_chat(viewer, "The [D.name] shows a [D.result].")

/// Old Peek at Dice verb: Peek at the dice under your cup.
/obj/item/storage/dicecup/proc/dicecup_verb_peek(mob/user, obj/item/held, datum/interaction/interaction)
	revealDice(user)

/// Old Reveal Dice verb: Reveal the dice hidden under your cup.
/obj/item/storage/dicecup/proc/dicecup_verb_reveal(mob/user, obj/item/held, datum/interaction/interaction)
	for(var/mob/living/player in viewers(3, user))
		to_chat(player, "[user] reveals their dice.")
		revealDice(player)


/obj/item/storage/dicecup/loaded/Initialize(mapload)
	. = ..()
	for(var/i = 1 to 5)
		new /obj/item/dice(src)

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
