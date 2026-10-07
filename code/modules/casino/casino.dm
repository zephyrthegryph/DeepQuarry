
//Original Casino Code created by Shadowfire117#1269 - Ported from CHOMPstation
//Modified by GhostActual#2055 for use with VOREstation

//
//Roulette Table
//
/obj/structure/casino_table
	name = "casino table"
	desc = "This is an unremarkable table for a casino."
	icon = 'icons/obj/casino.dmi'
	icon_state = "roulette_table"
	density = 1
	anchored = 1
	layer = TABLE_LAYER
	throwpass = 1
	var/item_place = 1 //allows items to be placed on the table, but not on benches.

CAPABILITIES(/obj/structure/casino_table)
	climb()
	op("interaction_place", item(/obj/item), label("Place"), then(PROC_REF(interaction_place)))

/// Old attackby: put the held item on the table.
/obj/structure/casino_table/proc/interaction_place(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(!item_place)
		return OP_PASS
	if(user.unEquip(W, 0, loc) && user.client?.prefs?.read_preference(/datum/preference/toggle/precision_placement))
		auto_align(W, dq_interaction_click_params(user)) // Precisely place item like this is a normal table
		return OP_PASS
	user.drop_item(loc)
	return OP_PASS

/obj/structure/casino_table/roulette_table
	name = "roulette"
	desc = "The roulette. Spin to try your luck."
	icon_state = "roulette_wheel"
	var/spin_state = "roulette_wheel_spinning"

	var/obj/item/roulette_ball/ball

	var/datum/effect/effect/system/confetti_spread
	var/confetti_strength = 5

CAPABILITIES(/obj/structure/casino_table/roulette_table)
	owns_one(nameof(confetti_spread), /datum/effect/effect/system)
	op("hand", hand(), ungated(), label("Spin"), needs(req(PROC_REF(can_spin_holds), because = PROC_REF(can_spin_refusal))), then(PROC_REF(interaction_hand)))
	op("insert_ball", item(/obj/item/roulette_ball), label("Insert a roulette ball"), then(PROC_REF(interaction_insert_ball)))
	op("roulette_table_remove_ball_effect", menu(), label("Remove Roulette Ball"), needs(req_adjacent(), req_capable(), req(PROC_REF(can_remove_ball_holds), because = PROC_REF(can_remove_ball_refusal))), then(PROC_REF(roulette_table_remove_ball_effect)))

/obj/structure/casino_table/roulette_table/examine(mob/user)
	.=..()
	if(ball)
		. += "It's currently using [ball.get_ball_desc()]."
	else
		. += "It doesn't have a ball."

/// Requirement: TRUE, or why the wheel can't be spun.
/obj/structure/casino_table/roulette_table/proc/can_spin(mob/user, atom/target, obj/item/held)
	if(task_busy(src))
		return "you cannot spin now, the roulette is already spinning"
	if(!ball)
		return "this roulette wheel has no ball"
	return TRUE

/// Requirement: TRUE, or why the ball can't be removed (the effect's silent guards pass here).
/obj/structure/casino_table/roulette_table/proc/can_remove_ball(mob/user, atom/target, obj/item/held)
	if(!user || !isturf(user.loc) || user.stat || user.restrained())
		return TRUE
	if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || isobserver(user))
		return TRUE
	if(task_busy(src))
		return "you cannot remove \the [ball] while [src] is spinning"
	return TRUE

/// Old attack_hand.
/// Requirement (was REQ_* can_spin): the legacy check answers TRUE to pass.
/obj/structure/casino_table/roulette_table/proc/can_spin_holds(datum/act/op/A)
	var/answer = can_spin(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_spin_holds refuses: the legacy check's text, else the clause's own reason.
/obj/structure/casino_table/roulette_table/proc/can_spin_refusal(datum/act/op/A)
	var/answer = can_spin(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/structure/casino_table/roulette_table/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, null, others = span_notice("%U% spins the roulette and throws [ball.get_ball_desc()] into it."))
	play_sfx(src.loc, SFX_MACHINES_ROULETTE)
	task_hold_busy(src, 5 SECONDS) // spinning: a hold claims the machine until the result
	ball.on_spin()
	icon_state = spin_state
	var/result = rand(0,36)
	if(ball.cheatball)
		result = ball.get_cheated_result()
	var/color = "gold"
	add_fingerprint(user)
	if((result > 0 && result < 11) || (result > 18 && result < 29))
		if(result % 2)
			color="red"
		else
			color="black"
	if((result > 10 && result < 19) || (result > 28 && result < 37))
		if(result % 2)
			color="black"
		else
			color="red"
	if(result == 37)
		result = "00"
	after(src, 5 SECONDS, PROC_REF(roulette_stops), with = list(result, color))
	return TRUE

/// Old attackby: load a ball into an empty wheel; with one already in, it goes on the table.
/obj/structure/casino_table/roulette_table/proc/interaction_insert_ball(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(ball)
		return OP_DECLINE
	if(!move_into(src, nameof(src.ball), W, user))
		return OP_DECLINE
	to_chat(user, span_notice("You insert [W] into [src]."))
	return OP_PASS

/// Requirement (was REQ_* can_remove_ball): the legacy check answers TRUE to pass.
/obj/structure/casino_table/roulette_table/proc/can_remove_ball_holds(datum/act/op/A)
	var/answer = can_remove_ball(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_remove_ball_holds refuses: the legacy check's text, else the clause's own reason.
/obj/structure/casino_table/roulette_table/proc/can_remove_ball_refusal(datum/act/op/A)
	var/answer = can_remove_ball(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/structure/casino_table/roulette_table/proc/roulette_table_remove_ball_effect(datum/act/op/A)
	var/mob/user = A.actor

	if(!user || !isturf(user.loc))
		return
	if(user.stat || user.restrained())
		return
	if(has_trait(user, TRAIT_AMBIENT_PEST_MOB) || (isobserver(user)))
		return

	if(ball)
		user.put_in_hands(ball)
		to_chat(user, span_notice("You remove \the [ball] from [src]."))
		rel_take(src, nameof(ball))
		return
	else
		to_chat(user, span_notice("There is no ball in [src]!"))
		return

/obj/structure/casino_table/roulette_table/long
	icon_state = "roulette_wheel_long"
	spin_state = "roulette_wheel_long_spinning"

/obj/structure/casino_table/roulette_long
	name = "roulette table"
	desc = "Roulette table."
	icon_state = "roulette_long"

/obj/structure/casino_table/roulette_chart
	name = "roulette chart"
	desc = "Roulette chart. Place your bets!"
	icon_state = "roulette_table"

/obj/item/roulette_ball
	name = "roulette ball"
	desc = "A small ball used for roulette wheel. This one is made of regular metal."
	var/ball_desc = "a small metal ball"
	icon = 'icons/obj/casino.dmi'
	icon_state = "roulette_ball"
	w_class = ITEMSIZE_TINY

	var/cheatball = FALSE

/obj/item/roulette_ball/proc/get_cheated_result()
	return rand(0,36) // No cheating by default //

/obj/item/roulette_ball/proc/get_ball_desc()
	return ball_desc

/obj/item/roulette_ball/proc/on_spin()
	return

/obj/item/roulette_ball/gold
	name = "golden roulette ball"
	desc = "A small ball used for roulette wheel. This one is particularly gaudy."
	ball_desc = "a shiny golden ball"
	icon_state = "roulette_ball_gold"

/obj/item/roulette_ball/red
	name = "red roulette ball"
	desc = "A small ball used for roulette wheel. This one is ornate red."
	ball_desc = "a striped red ball"
	icon_state = "roulette_ball_red"

/obj/item/roulette_ball/orange
	name = "orange roulette ball"
	desc = "A small ball used for roulette wheel. This one is ornate orange."
	ball_desc = "a striped orange ball"
	icon_state = "roulette_ball_orange"

/obj/item/roulette_ball/green
	name = "green roulette ball"
	desc = "A small ball used for roulette wheel. This one is ornate green."
	ball_desc = "a smooth green ball"
	icon_state = "roulette_ball_green"

/obj/item/roulette_ball/blue
	name = "blue roulette ball"
	desc = "A small ball used for roulette wheel. This one is ornate blue."
	ball_desc = "a striped blue ball"
	icon_state = "roulette_ball_blue"

/obj/item/roulette_ball/yellow
	name = "yellow roulette ball"
	desc = "A small ball used for roulette wheel. This one is ornate yellow."
	ball_desc = "a smooth yellow ball"
	icon_state = "roulette_ball_yellow"

/obj/item/roulette_ball/purple
	name = "purple roulette ball"
	desc = "A small ball used for roulette wheel. This one is ornate purple."
	ball_desc = "a dotted purple ball"
	icon_state = "roulette_ball_purple"

/obj/item/roulette_ball/planet
	name = "planet roulette ball"
	desc = "A small ball used for roulette wheel. This one looks like a small earth-like planet."
	ball_desc = "a planet-like ball"
	icon_state = "roulette_ball_earth"

/obj/item/roulette_ball/moon
	name = "moon roulette ball"
	desc = "A small ball used for roulette wheel. This one looks like a small moon."
	ball_desc = "a moon-like ball"
	icon_state = "roulette_ball_moon"

/obj/item/roulette_ball/hollow
	name = "glass roulette ball"
	desc = "A small ball used for roulette wheel. This one is made of glass and seems to be openable."
	ball_desc = "a small glass ball"
	icon_state = "roulette_ball_glass"

	var/obj/item/holder/trapped

/obj/item/roulette_ball/hollow/examine(mob/user)
	.=..()
	if(trapped)
		. += "You can see [trapped] trapped inside!"
	else
		. += "It appears to be empty."

/obj/item/roulette_ball/hollow/get_ball_desc()
	.=..()
	if(trapped && trapped.held_mob)
		. += " with [trapped.name] trapped within"
	return

/// Old attackby.
/obj/item/roulette_ball/hollow/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/holder))
		var/obj/item/holder/H = W
		if(!H.held_mob)
			to_chat(user, span_warning("This holder has nobody in it? Yell at a developer!"))
			return INTERACTION_HANDLED_PASS
		if(H.held_mob.get_effective_size(TRUE) > 50)
			to_chat(user, span_warning("\The [H] is too big to fit inside!"))
			return INTERACTION_HANDLED_PASS
		if(!move_into(src, nameof(src.trapped), H, user))
			return INTERACTION_HANDLED_PASS
		to_chat(user, span_notice("You trap \the [H] inside the glass roulette ball."))
		to_chat(H.held_mob, span_warning("\The [user] traps you inside a glass roulette ball!"))
		update_icon()
	return INTERACTION_HANDLED_PASS

DECLARE_APPEARANCE_PROC(/obj/item/roulette_ball/hollow, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/roulette_ball/hollow/appearance_overlays()
	. = list()
	if(trapped && trapped.held_mob)
		icon_state = "roulette_ball_glass_full"
	else
		icon_state = "roulette_ball_glass"

DECLARE_INTERACTIONS(/obj/item/roulette_ball/hollow, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item), REQ_FIELD_NOT("trapped", "this ball already has something trapped in it")), \
)

/// Old attack_self.
/obj/item/roulette_ball/hollow/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!trapped)
		to_chat(user, span_notice("\The [src] is empty!"))
		return TRUE
	else
		user.put_in_hands(trapped)
		if(trapped.held_mob)
			to_chat(user, span_notice("You take \the [trapped] out of the glass roulette ball."))
			to_chat(trapped.held_mob, span_notice("\The [user] takes you out of a glass roulette ball."))
		rel_take(src, nameof(trapped))
		update_icon()
	return TRUE

/obj/item/roulette_ball/hollow/on_holder_escape()
	rel_take(src, nameof(trapped))
	update_icon()

/obj/item/roulette_ball/hollow/on_spin()
	if(trapped && trapped.held_mob)
		to_chat(trapped.held_mob, span_critical("THE WHOLE WORLD IS SENT WHIRLING AS THE ROULETTE SPINS!!!"))

CAPABILITIES(/obj/item/roulette_ball/hollow)
	owns_one(nameof(trapped), on_destroy = ON_DESTROY_SPILL)

/obj/item/roulette_ball/cheat
	cheatball = TRUE

/obj/item/roulette_ball/cheat/first_twelve
	desc = "A small ball used for roulette wheel. This one is made of regular metal. Its weighted to only land on first 12."

/obj/item/roulette_ball/cheat/first_twelve/get_cheated_result()
	return pick(list(1,2,3,4,5,6,7,8,9,10,11,12))

/obj/item/roulette_ball/cheat/second_twelve
	desc = "A small ball used for roulette wheel. This one is made of regular metal. Its weighted to only land on second 12."

/obj/item/roulette_ball/cheat/second_twelve/get_cheated_result()
	return pick(list(13,14,15,16,17,18,19,20,21,22,23,24))

/obj/item/roulette_ball/cheat/third_twelve
	desc = "A small ball used for roulette wheel. This one is made of regular metal. Its weighted to only land on third 12."

/obj/item/roulette_ball/cheat/third_twelve/get_cheated_result()
	return pick(list(25,26,27,28,29,30,31,32,33,34,35,36))

/obj/item/roulette_ball/cheat/zeros
	desc = "A small ball used for roulette wheel. This one is made of regular metal. Its weighted to only land on 0 or 00."

/obj/item/roulette_ball/cheat/zeros/get_cheated_result()
	return pick(list(0))

/obj/item/roulette_ball/cheat/red
	desc = "A small ball used for roulette wheel. This one is made of regular metal. Its weighted to only land on red."

/obj/item/roulette_ball/cheat/red/get_cheated_result()
	return pick(list(1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36))

/obj/item/roulette_ball/cheat/black
	desc = "A small ball used for roulette wheel. This one is made of regular metal. Its weighted to only land on black."

/obj/item/roulette_ball/cheat/black/get_cheated_result()
	return pick(list(2,4,6,8,10,11,13,15,17,20,22,24,26,28,29,31,33,35))

/obj/item/roulette_ball/cheat/even
	desc = "A small ball used for roulette wheel. This one is made of regular metal. Its weighted to only land on even."

/obj/item/roulette_ball/cheat/even/get_cheated_result()
	return pick(list(2,4,6,8,10,12,14,16,18,20,22,24,26,28,30,32,34,36))

/obj/item/roulette_ball/cheat/odd
	desc = "A small ball used for roulette wheel. This one is made of regular metal. Its weighted to only land on odd."

/obj/item/roulette_ball/cheat/odd/get_cheated_result()
	return pick(list(1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31,33,35))

//
//Blackjack table
//
/obj/structure/casino_table/blackjack_l
	icon = 'icons/obj/casino_ch.dmi'
	name = "gambling table"
	desc = "Gambling table, try your luck and skills!"
	icon_state = "blackjack_l"

/obj/structure/casino_table/blackjack_m
	icon = 'icons/obj/casino_ch.dmi'
	name = "gambling table"
	desc = "Gambling table, try your luck and skills!"
	icon_state = "blackjack_m"

/obj/structure/casino_table/blackjack_r
	icon = 'icons/obj/casino_ch.dmi'
	name = "gambling table"
	desc = "Gambling table, try your luck and skills!"
	icon_state = "blackjack_r"

//
//Craps table
//
/obj/structure/casino_table/craps
	name = "craps table"
	desc = "A padded table designed for dice games!"
	icon_state = "craps_table"

//
//Wheel. Of. FORTUNE!
//
/obj/machinery/wheel_of_fortune
	name = "wheel of fortune"
	desc = "The Wheel of Fortune! Insert chips and may fortune favour the lucky one at the next lottery!"
	icon = 'icons/obj/64x64.dmi'
	icon_state = "wheel_of_fortune"
	density = 1
	anchored = 1
	pixel_x = -16

	req_access = list(300)
	var/interval = 1
	var/public_spin = 0
	var/lottery_sale = "disabled"
	var/lottery_price = 100
	var/lottery_entries = 0
	var/list/lottery_tickets
	var/list/lottery_tickets_ckeys

	var/datum/effect/effect/system/confetti_spread
	var/confetti_strength = 15

CAPABILITIES(/obj/machinery/wheel_of_fortune)
	owns_one(nameof(confetti_spread), /datum/effect/effect/system)

EXTEND_INTERACTIONS(/obj/machinery/wheel_of_fortune, \
	INTERACT_HAND_UNGATED("Use", PROC_REF(interaction_use), REQ_BECAUSE(REQ_TARGET_STATE(/obj/machinery/wheel_of_fortune/proc/not_spinning), "the wheel of fortune is already spinning")), \
	INTERACT_INSERT(list(/obj/item/card/id, /obj/item/pda), PROC_REF(interaction_id), "Management controls", REQ_ON(PRED_TARGET, /obj/machinery/wheel_of_fortune/proc/not_busy_and_actor_able, null), REQ_TARGET_STATE(/obj/machinery/wheel_of_fortune/proc/can_manage)), \
	INTERACT_INSERT(/obj/item/spacecasinocash, PROC_REF(interaction_cash), "Buy lottery ticket", REQ_ON(PRED_TARGET, /obj/machinery/wheel_of_fortune/proc/not_busy_and_actor_able, null), REQ_TARGET_STATE(/obj/machinery/wheel_of_fortune/proc/can_buy_ticket)), \
	INTERACT_VERB("Change interval", PROC_REF(interaction_setinterval_verb), REQ_PROC(/proc/dq_actor_can_act, "you can't do that right now")), \
)

/// Requirement: the wheel isn't mid-spin.
/obj/machinery/wheel_of_fortune/proc/not_spinning(mob/user, atom/target, obj/item/held)
	return !task_busy(src)

/obj/machinery/wheel_of_fortune/proc/interaction_use(mob/user, obj/item/held, datum/interaction/interaction)
	return wheel_use_stage(user, held, interaction, list())

/obj/machinery/wheel_of_fortune/proc/wheel_use_stage(mob/user, obj/item/held, datum/interaction/interaction, list/wheel_answers)
	if(user.incapacitated())
		return TRUE
	if(ishuman(user) || isrobot(user))
		if(!("k410" in wheel_answers))
			open_request(src, /datum/prompt/choice/wheel_review, PROC_REF(wheel_use_answered), answerer = user, wheel_operator = user, wheel_answers = wheel_answers, wheel_key = "k410", wheel_held = held, wheel_interaction = interaction, question = "Choose what to do", title = "Wheel Of Fortune", choices = list("Spin the Wheel! (Not Lottery)", "Set the interval", "Cancel"))
			return
		var/_answer_k410 = wheel_answers["k410"]
		if(isnull(_answer_k410))
			return
		switch(_answer_k410)
			if("Cancel")
				return TRUE
			if("Spin the Wheel! (Not Lottery)")
				if(public_spin == 0)
					to_chat(user,span_notice("The Wheel makes a sad beep, public spins are not enabled right now..."))
					return TRUE
				to_chat(user,span_notice("You spin the wheel!"))
				spin_the_wheel("not_lottery")
			if("Set the interval")
				wheel_interval_stage(user, list())
	return TRUE

/// Requirement: the swiped card carries management access.
/obj/machinery/wheel_of_fortune/proc/can_manage(mob/user, atom/target, obj/item/held)
	if(!check_access(held))
		return "access denied"
	return TRUE

/obj/machinery/wheel_of_fortune/proc/not_busy_and_actor_able(mob/actor, atom/target, obj/item/held)
	if (task_busy(src))
		return "the wheel of fortune is already spinning!"
	if(actor.incapacitated())
		return FALSE
	return TRUE

/obj/machinery/wheel_of_fortune/proc/interaction_id(mob/user, obj/item/W, datum/interaction/interaction)
	return wheel_management_stage(user, W, interaction, list())

/obj/machinery/wheel_of_fortune/proc/wheel_management_stage(mob/user, obj/item/W, datum/interaction/interaction, list/wheel_answers)
	to_chat(user, span_warning("Proper access, allowed staff controls."))
	if(ishuman(user) || isrobot(user))
		if(!("k445" in wheel_answers))
			open_request(src, /datum/prompt/choice/wheel_review, PROC_REF(wheel_management_answered), answerer = user, wheel_operator = user, wheel_answers = wheel_answers, wheel_key = "k445", wheel_held = W, wheel_interaction = interaction, question = "Choose what to do (Management)", title = "Wheel Of Fortune (Management)", choices = list("Spin the Lottery Wheel!", "Toggle Lottery Sales", "Toggle Public Spins", "Reset Lottery", "Cancel"))
			return
		var/_answer_k445 = wheel_answers["k445"]
		if(isnull(_answer_k445))
			return
		switch(_answer_k445)
			if("Cancel")
				return TRUE
			if("Spin the Lottery Wheel!")
				to_chat(user,span_notice("You spin the wheel for the lottery!"))
				spin_the_wheel("lottery")

			if("Toggle Lottery Sales")
				if(lottery_sale == "disabled")
					lottery_sale = "enabled"
					to_chat(user,span_notice("Public Lottery sale has been enabled."))
					return TRUE
				lottery_sale = "disabled"
				to_chat(user,span_notice("Public Lottery sale has been disabled."))

			if("Toggle Public Spins")
				if(public_spin == 0)
					public_spin = 1
					to_chat(user,span_notice("Public spins has been enabled."))
					return TRUE
				public_spin = 0
				to_chat(user,span_notice("Public spins has been disabled."))

			if("Reset Lottery")
				if(!("k469" in wheel_answers))
					open_request(src, /datum/prompt/choice/wheel_review, PROC_REF(wheel_management_answered), answerer = user, wheel_operator = user, wheel_answers = wheel_answers, wheel_key = "k469", wheel_held = W, wheel_interaction = interaction, question = "Are you sure you want to reset Lottery?", title = "Confirm Lottery Reset", choices = list("Yes", "No"), buttons = TRUE)
					return
				var/confirm = wheel_answers["k469"]
				if(isnull(confirm))
					return
				if(confirm == "Yes")
					to_chat(user, span_warning("Lottery has been Reset!"))
					lottery_entries = 0
					lottery_tickets = null
					lottery_tickets_ckeys = null
	return TRUE

/// Requirement: TRUE, or why no ticket can be bought.
/obj/machinery/wheel_of_fortune/proc/can_buy_ticket(mob/user, atom/target, obj/item/held)
	if(lottery_sale == "disabled")
		return "lottery sales are currently disabled"
	if(user.client && (user.client.ckey in lottery_tickets_ckeys))
		return "the scanner beeps in an upset manner, you already have a ticket"
	return TRUE

/obj/machinery/wheel_of_fortune/proc/interaction_cash(mob/user, obj/item/spacecasinocash/C, datum/interaction/interaction)
	if(!user.client)
		return TRUE

	insert_chip(C, user)
	return TRUE

/obj/machinery/wheel_of_fortune/proc/insert_chip(obj/item/spacecasinocash/cashmoney, mob/user)
	if(!user.client)
		return
	if (task_busy(src))
		to_chat(user,span_notice("The Wheel of Fortune is busy, wait for it to be done to buy a lottery ticket."))
		return
	if(cashmoney.worth < lottery_price)
		to_chat(user,span_notice("You dont have enough chips to buy a lottery ticket!"))
		return

	to_chat(user,span_notice("You put [lottery_price] credits worth of chips into the Wheel of Fortune and it pings to notify of your lottery ticket registered!"))
	cashmoney.worth -= lottery_price
	cashmoney.update_icon()

	if(cashmoney.worth <= 0)
		consume(cashmoney, user)

	lottery_entries++
	LAZYADD(lottery_tickets, "Number.[lottery_entries] [user.name]")
	LAZYADD(lottery_tickets_ckeys, user.client.ckey)

/obj/machinery/wheel_of_fortune/proc/spin_the_wheel(mode)
	var/result = 0

	if(mode == "not_lottery")
		task_hold_busy(src, 5 SECONDS) // spinning: a hold claims the machine until the result
		icon_state = "wheel_of_fortune_spinning"
		result = rand(1,interval)

		after(src, 5 SECONDS, PROC_REF(wheel_stops), with = list("The wheel of fortune stops spinning, the number is [result]!"))

	if(mode == "lottery")
		if(lottery_entries == 0)
			visible_message(span_notice("There are no tickets in the system!"))
			return

		task_hold_busy(src, 5 SECONDS) // spinning: a hold claims the machine until the result
		icon_state = "wheel_of_fortune_spinning"
		result = pick(lottery_tickets)

		after(src, 5 SECONDS, PROC_REF(wheel_stops), with = list("The wheel of fortune stops spinning, and the winner is [result]!"))

/obj/machinery/wheel_of_fortune/proc/interaction_setinterval_verb(mob/user, obj/item/held, datum/interaction/interaction)
	interaction_setinterval(user)
	return TRUE

/// Old verb body, also called directly from the attack_hand "Set the interval" menu option.
/obj/machinery/wheel_of_fortune/proc/interaction_setinterval(mob/user)
	return wheel_interval_stage(user, list())

/obj/machinery/wheel_of_fortune/proc/wheel_interval_stage(mob/user, list/wheel_answers)
	if(user.incapacitated())
		return
	if(ishuman(user) || isrobot(user))
		if(!("k556" in wheel_answers))
			open_request(src, /datum/prompt/number/wheel_review, PROC_REF(wheel_interval_answered), answerer = user, wheel_operator = user, wheel_answers = wheel_answers, wheel_key = "k556", question = "Put the desired interval (1-1000)", title = "Set Interval")
			return
		var/new_interval = wheel_answers["k556"]
		if(isnull(new_interval))
			return
		if(!isnum(new_interval) || new_interval < 1 || new_interval > 1000)
			to_chat(user, span_notice("Invalid interval."))
			return
		interval = new_interval
		to_chat(user, span_notice("You set the interval to [interval]"))
	return

//
//Sentient Prize Terminal
//
/obj/machinery/casinosentientprize_handler
	name = "Sentient Prize Automated Sales Machinery"
	desc = "The Sentient Prize Automated Sales Machinery, also known as SPASM! Here one can see who is on sale as sentinet prizes, as well as selling self and also buying prizes."
	icon = 'icons/obj/casino_ch.dmi'
	icon_state = "casinoslave_hub_off"
	density = 0
	anchored = 1
	req_access = list(300)

	var/casinosentientprize_sale = "disabled"
	var/casinosentientprize_price = 100
	var/list/collar_list
	var/list/sentientprizes_ckeys_list //Same trick as lottery, to keep life simple
	var/obj/item/clothing/accessory/collar/casinosentientprize/selected_collar = null

CAPABILITIES(/obj/machinery/casinosentientprize_handler)
	ref_many(nameof(collar_list), /obj/item/clothing/accessory/collar/casinosentientprize)

EXTEND_INTERACTIONS(/obj/machinery/casinosentientprize_handler, \
	INTERACT_HAND_UNGATED("Use", PROC_REF(interaction_use), REQ_TARGET_STATE(/obj/machinery/casinosentientprize_handler/proc/can_use_spasm)), \
	INTERACT_INSERT(/obj/item/spacecasinocash, PROC_REF(interaction_cash), "Buy prize", REQ_ON(PRED_ACTOR, /obj/machinery/casinosentientprize_handler/proc/actor_not_incapacitated, null), REQ_TARGET_STATE(/obj/machinery/casinosentientprize_handler/proc/can_buy_prize)), \
	INTERACT_INSERT(/obj/item/clothing/accessory/collar/casinosentientprize, PROC_REF(interaction_collar), "Release prize", REQ_ON(PRED_ACTOR, /obj/machinery/casinosentientprize_handler/proc/actor_not_incapacitated, null), REQ_TARGET_STATE(/obj/machinery/casinosentientprize_handler/proc/can_release_collar)), \
	INTERACT_INSERT(list(/obj/item/card/id, /obj/item/pda), PROC_REF(interaction_id), "Management controls", REQ_ON(PRED_ACTOR, /obj/machinery/casinosentientprize_handler/proc/actor_not_incapacitated, null), REQ_TARGET_STATE(/obj/machinery/casinosentientprize_handler/proc/can_manage)), \
)

/// Requirement: TRUE, or why the SPASM can't be used (an incapacitated user is refused silently by the effect).
/obj/machinery/casinosentientprize_handler/proc/can_use_spasm(mob/user, atom/target, obj/item/held)
	if(user.incapacitated())
		return TRUE
	if(casinosentientprize_sale == "disabled")
		return "the SPASM is disabled"
	return TRUE

/obj/machinery/casinosentientprize_handler/proc/interaction_use(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(user.incapacitated())
		return TRUE

	if(ishuman(user) || isrobot(user))
		var/_answer_k604 = rerun_ask(user, "k604", PROC_REF(interaction_use), args, /datum/prompt/choice, question = "Choose what to do", title = "SPASM", choices = list("Show selected Prize", "Select Prize", "Become Prize (Please examine yourself first)", "Cancel"))
		if(isnull(_answer_k604))
			return
		switch(_answer_k604)
			if("Cancel")
				return TRUE
			if("Show selected Prize")
				if(QDELETED(selected_collar))
					if(selected_collar)
						rel_remove(src, nameof(collar_list), selected_collar)
						LAZYREMOVE(sentientprizes_ckeys_list, selected_collar.sentientprizeckey)
						rel_clear(src, nameof(selected_collar))
					to_chat(user, span_warning("No collar is currently selected or the currently selected one has been destroyed or disabled."))
					return TRUE
				to_chat(user, span_warning("Sentient Prize information"))
				to_chat(user, span_notice("Name: [selected_collar.sentientprizename]"))
				to_chat(user, span_notice("Description: [selected_collar.sentientprizeflavor]"))
				to_chat(user, span_notice("OOC: [selected_collar.sentientprizeooc]"))
				to_chat(user, span_notice("Allows item prize TF: [selected_collar.sentientprizeitemtf ? "Yes (you may choose to turn your prize into an item when claiming!)" : "No"]"))
				if(selected_collar.ownername != null)
					to_chat(user, span_warning("This prize is already owned by [selected_collar.ownername]"))

			if("Select Prize")
				var/_answer_k624 = rerun_ask(user, "k624", PROC_REF(interaction_use), args, /datum/prompt/choice, question = "Select a prize", title = "Chose a collar", choices = collar_list || list())
				if(isnull(_answer_k624))
					return
				rel_set(src, nameof(selected_collar), _answer_k624)
				if(QDELETED(selected_collar))
					rel_remove(src, nameof(collar_list), selected_collar)
					LAZYREMOVE(sentientprizes_ckeys_list, selected_collar?.sentientprizeckey)
					to_chat(user, span_warning("No collars to chose, or selected collar has been destroyed or deactived, selection has been removed from list."))
					rel_clear(src, nameof(selected_collar))
					return TRUE

			if("Become Prize (Please examine yourself first)") //Its awkward, but no easy way to obtain flavor_text due to server not loading text of mob until its been examined at least once.
				if(!user.client)
					return TRUE
				var/safety_ckey = user.client.ckey
				if(safety_ckey in sentientprizes_ckeys_list)
					to_chat(user, span_warning("The SPASM beeps in an upset manner, you already have a collar!"))
					return TRUE
				var/confirm = rerun_ask(user, "k639", PROC_REF(interaction_use), args, /datum/prompt/choice, question = "Are you sure you want to become a sentient prize?", title = "Confirm Sentient Prize", choices = list("Yes", "No"), buttons = TRUE)
				if(isnull(confirm))
					return
				if(!confirm)
					return TRUE
				if(confirm == "No")
					to_chat(user, span_warning("The SPASM beeps in a sad manner at your impolite decline..."))
					return TRUE
				var/confirmitemtf = rerun_ask(user, "k645", PROC_REF(interaction_use), args, /datum/prompt/choice, question = "Would you like to allow others to turn you into an item upon claiming you if they choose to?", title = "Confirm Item TF Preference", choices = list("Yes", "No"), buttons = TRUE)
				if(isnull(confirmitemtf))
					return
				var/allowitemtf = FALSE
				if(confirmitemtf == "Yes")
					allowitemtf = TRUE
				if(safety_ckey in sentientprizes_ckeys_list)
					to_chat(user, span_warning("The SPASM beeps in an upset manner, you already have a collar!"))
					return TRUE
				to_chat(user, span_warning("You are now a prize!"))
				LAZYADD(sentientprizes_ckeys_list, user.ckey)
				var/obj/item/clothing/accessory/collar/casinosentientprize/C = new(src.loc)
				C.sentientprizename = "[user.name]"
				C.sentientprizeckey = "[user.ckey]"
				C.sentientprizeflavor = user.flavor_text
				C.sentientprizeooc = user.identity().ooc_notes
				C.sentientprizeitemtf = allowitemtf
				C.name = "Sentient Prize Collar: Available! [user.name] purchaseable at the SPASM!"
				C.desc = "Golden Goose Sentient Prize collar. The tags shows in flashy colorful text the wearer is [user.name] and is currently available to buy at the Sentient Prize Automated Sales Machinery!"
				C.icon_state = "casinoslave_available"
				C.update_icon()
				rel_add(src, nameof(collar_list), C)

				spawn_casinochips(casinosentientprize_price, src.loc)
	return TRUE

/// Requirement: TRUE, or why no prize can be bought.
/obj/machinery/casinosentientprize_handler/proc/can_buy_prize(mob/user, atom/target, obj/item/held)
	if(casinosentientprize_sale == "disabled")
		return "sentient prize sales are currently disabled"
	if(!selected_collar)
		return "select a prize first"
	return TRUE

/obj/machinery/casinosentientprize_handler/proc/actor_not_incapacitated(mob/actor, atom/target, obj/item/held)
	return !actor.incapacitated()

/obj/machinery/casinosentientprize_handler/proc/interaction_cash(mob/user, obj/item/W, datum/interaction/interaction)
	if(!selected_collar.ownername)
		if(!user.client)
			return TRUE
		var/obj/item/spacecasinocash/C = W
		if(user.client.ckey == selected_collar.sentientprizeckey)
			insert_chip(C, user, "selfbuy")
			return TRUE
		insert_chip(C, user, "buy")
		return TRUE
	to_chat(user, span_warning("This Sentient Prize is already owned! If you are the owner you can release the prize by swiping the collar on the SPASM!"))
	return TRUE

/// Requirement: the collar belongs to the user (as prize or owner).
/obj/machinery/casinosentientprize_handler/proc/can_release_collar(mob/user, atom/target, obj/item/clothing/accessory/collar/casinosentientprize/held)
	if(user.name != held.sentientprizename && user.name != held.ownername)
		return "this sentient prize collar isn't yours, please give it to the one it tagged for, belongs to, or a casino staff member"
	return TRUE

/obj/machinery/casinosentientprize_handler/proc/interaction_collar(mob/user, obj/item/clothing/accessory/collar/casinosentientprize/C, datum/interaction/interaction)
	if(user.name == C.sentientprizename)
		if(!C.ownername)
			to_chat(user,span_notice("If collar isn't disabled and entry removed, please select your entry and insert chips. Or contact staff if you need assistance."))
			return TRUE
		if(C.sentientprizename != C.ownername)
			to_chat(user,span_notice("If collar isn't disabled and entry removed, please ask your owner to free you with collar swipe on the SPASM, or contact staff if you need assistance."))
			return TRUE
	if(user.name == C.ownername)
		var/confirm = rerun_ask(user, "k717", PROC_REF(interaction_collar), args, /datum/prompt/choice, question = "Are you sure you want to wipe [C.sentientprizename] entry?", title = "Confirm Sentient Prize Release", choices = list("Yes", "No"), buttons = TRUE)
		if(isnull(confirm))
			return
		if(confirm == "Yes")
			to_chat(user, span_warning("[C.sentientprizename] collar has been deleted from registry!"))
			C.icon_state = "casinoslave"
			C.update_icon()
			C.name = "disabled Sentient Prize Collar: [C.sentientprizename]"
			C.desc = "A collar worn by sentient prizes on the Golden Goose Casino. The tag says its registered to [C.sentientprizename], but harsh red text informs you its been disabled."
			LAZYREMOVE(sentientprizes_ckeys_list, C.sentientprizeckey)
			C.sentientprizeckey = null
			rel_remove(src, nameof(collar_list), C)
	return TRUE

/// Requirement: the swiped card carries management access.
/obj/machinery/casinosentientprize_handler/proc/can_manage(mob/user, atom/target, obj/item/held)
	if(!check_access(held))
		return "access denied"
	return TRUE

/obj/machinery/casinosentientprize_handler/proc/interaction_id(mob/user, obj/item/W, datum/interaction/interaction)
	to_chat(user, span_warning("Proper access, allowed staff controls."))
	if(ishuman(user) || isrobot(user))
		var/_answer_k743 = rerun_ask(user, "k743", PROC_REF(interaction_id), args, /datum/prompt/choice, question = "Choose what to do (Management)", title = "SPASM (Management)", choices = list("Toggle Sentient Prize Sales", "Wipe Selected Prize Entry", "Change Prize Value", "Cancel"))
		if(isnull(_answer_k743))
			return
		switch(_answer_k743)
			if("Cancel")
				return TRUE

			if("Toggle Sentient Prize Sales")
				if(casinosentientprize_sale == "disabled")
					casinosentientprize_sale = "enabled"
					icon_state = "casinoslave_hub_on"
					to_chat(user,span_notice("Prize sale has been enabled."))
				else
					casinosentientprize_sale = "disabled"
					icon_state = "casinoslave_hub_off"
					to_chat(user,span_notice("Prize sale has been disabled."))

			if("Wipe Selected Prize Entry")
				if(!selected_collar)
					to_chat(user, span_warning("No collar selected!"))
					return TRUE
				if(QDELETED(selected_collar))
					rel_remove(src, nameof(collar_list), selected_collar)
					LAZYREMOVE(sentientprizes_ckeys_list, selected_collar.sentientprizeckey)
					to_chat(user, span_warning("Collar has been destroyed!"))
					rel_clear(src, nameof(selected_collar))
					return TRUE
				var/safety_ckey = selected_collar.sentientprizeckey
				var/confirm = rerun_ask(user, "k770", PROC_REF(interaction_id), args, /datum/prompt/choice, question = "Are you sure you want to wipe [selected_collar.sentientprizename] entry?", title = "Confirm Sentient Prize", choices = list("Yes", "No"), buttons = TRUE)
				if(isnull(confirm))
					return
				if(confirm == "Yes")
					if(safety_ckey == selected_collar.sentientprizeckey)
						to_chat(user, span_warning("[selected_collar.sentientprizename] collar has been deleted from registry!"))
						selected_collar.icon_state = "casinoslave"
						selected_collar.update_icon()
						selected_collar.name = "disabled Sentient Prize Collar: [selected_collar.sentientprizename]"
						selected_collar.desc = "A collar worn by sentient prizes on the Golden Goose Casino. The tag says its registered to [selected_collar.sentientprizename], but harsh red text informs you its been disabled."
						LAZYREMOVE(sentientprizes_ckeys_list, selected_collar.sentientprizeckey)
						selected_collar.sentientprizeckey = null
						rel_remove(src, nameof(collar_list), selected_collar)
						rel_clear(src, nameof(selected_collar))
						return TRUE
					to_chat(user, span_warning("Registry deletion aborted! Changed collar selection!"))
					return TRUE

			if("Change Prize Value")
				setprice(user)
	return TRUE

/// The prize customises the item they become (each question optional), then is transformed.
/obj/machinery/casinosentientprize_handler/proc/do_item_tf(mob/living/sentient_prize, target_item_name)
	var/item_type = GLOB.item_tf_options[target_item_name]
	if(!ispath(item_type))
		return
	var/obj/item/item_path = item_type
	var/datum/prompt/text/casino_item_tf/ask = open_request(src, /datum/prompt/text/casino_item_tf, PROC_REF(item_tf_text_entered), answerer = sentient_prize, tf_type = item_type, question = "Choose your item name for \the [initial(item_path.name)] (Leave blank or cancel to use its default name)", title = "TF Item Name")
	if(ask?.is_open())
		ask.tf_opened = TRUE

/// A genuine close supplies the old optional default; rejection before opening does not.
/proc/casino_item_tf_continues(datum/act/request/A, opened)
	var/mob/living/prize = A.request.answerer
	if(!istype(prize) || QDELETED(prize))
		return FALSE
	if(A.answer)
		return TRUE
	if(!opened || A.request.outcome != REQ_CANCELLED || !isnull(A.request.value))
		return FALSE
	return isnull(request_recheck(A.request))

/proc/casino_item_tf_refusal(datum/request/R)
	var/mob/living/prize = R.answerer
	if(!istype(prize) || QDELETED(prize) || !R.owner || QDELETED(R.owner))
		return "gone"
	return prize.stat == DEAD ? "dead" : null

/datum/prompt/text/casino_item_tf
	timeout = 0
	recheck_on_open = TRUE
	var/tf_type
	var/tf_name
	var/tf_description = FALSE
	var/tf_opened = FALSE

/datum/prompt/text/casino_item_tf/recheck_extra()
	return casino_item_tf_refusal(src)

/datum/prompt/text/casino_item_tf/normalize(given)
	return istext(given) ? given : null

/obj/machinery/casinosentientprize_handler/proc/item_tf_text_entered(datum/act/request/A)
	var/datum/prompt/text/casino_item_tf/ask = A.request
	if(!casino_item_tf_continues(A, ask.tf_opened))
		return
	var/text = A.answer ? ask.value : ""
	if(!ask.tf_description)
		var/obj/item/item_path = ask.tf_type
		var/datum/prompt/text/casino_item_tf/description_request = open_request(src, /datum/prompt/text/casino_item_tf, PROC_REF(item_tf_text_entered), answerer = ask.answerer, tf_type = ask.tf_type, tf_name = text, tf_description = TRUE, title = "TF Item Description", question = "Choose your item description for \the [initial(item_path.name)] (Leave blank or cancel to use its default description)")
		if(description_request?.is_open())
			description_request.tf_opened = TRUE
		return
	var/datum/prompt/choice/casino_item_tf/recolor_request = open_request(src, /datum/prompt/choice/casino_item_tf, PROC_REF(item_tf_recolor_answered), answerer = ask.answerer, tf_type = ask.tf_type, tf_name = ask.tf_name, tf_desc = text, title = "Item TF Color", question = "Do you want to customize your item's color?")
	if(recolor_request?.is_open())
		recolor_request.tf_opened = TRUE

/datum/prompt/choice/casino_item_tf
	timeout = 0
	recheck_on_open = TRUE
	buttons = TRUE
	choices = list("Yes", "No")
	var/tf_type
	var/tf_name
	var/tf_desc
	var/tf_opened = FALSE

/datum/prompt/choice/casino_item_tf/recheck_extra()
	return casino_item_tf_refusal(src)

/obj/machinery/casinosentientprize_handler/proc/item_tf_recolor_answered(datum/act/request/A)
	var/datum/prompt/choice/casino_item_tf/ask = A.request
	if(!casino_item_tf_continues(A, ask.tf_opened))
		return
	if(!A.answer || ask.value != "Yes")
		item_tf_transform(ask.answerer, ask.tf_type, ask.tf_name, ask.tf_desc, null)
		return
	var/obj/item/item_path = ask.tf_type
	var/datum/prompt/color/casino_item_tf/next = open_request(src, /datum/prompt/color/casino_item_tf, PROC_REF(item_tf_color_picked), answerer = ask.answerer, tf_type = ask.tf_type, tf_name = ask.tf_name, tf_desc = ask.tf_desc, title = "Item TF Color", question = "Choose the color for your item.", default = initial(item_path.color) || "#000000")
	if(next?.is_open())
		next.tf_opened = TRUE

/datum/prompt/color/casino_item_tf
	timeout = 0
	recheck_on_open = TRUE
	var/tf_type
	var/tf_name
	var/tf_desc
	var/tf_opened = FALSE

/datum/prompt/color/casino_item_tf/recheck_extra()
	return casino_item_tf_refusal(src)

/datum/prompt/color/casino_item_tf/normalize(given)
	return given

/datum/prompt/color/casino_item_tf/refusal(given)
	return null

/datum/prompt/color/casino_item_tf/present(mob/user)
	var/datum/tgui_color_picker/prompt/picker = new(user, question, title || "Pick a color", default || "#000000", timeout, TRUE, GLOB.tgui_always_state)
	rel_set(picker, nameof(picker.prompt), src)
	picker.tgui_interact(user)
	return picker

/obj/machinery/casinosentientprize_handler/proc/item_tf_color_picked(datum/act/request/A)
	var/datum/prompt/color/casino_item_tf/ask = A.request
	if(!casino_item_tf_continues(A, ask.tf_opened))
		return
	item_tf_transform(ask.answerer, ask.tf_type, ask.tf_name, ask.tf_desc, A.answer ? ask.value : "")

/obj/machinery/casinosentientprize_handler/proc/item_tf_transform(mob/living/sentient_prize, item_type, item_name, item_desc, item_color)
	var/obj/item/newitem = new item_type(get_turf(sentient_prize)) // This might be a bad idea, but if the prize is in something/someone it would be potentially diastrous to use loc. Better to move 'em out than move it in!
	if(LAZYLEN(item_name))
		newitem.name = item_name
	if(LAZYLEN(item_desc))
		newitem.desc = item_desc
	if(item_color)
		newitem.color = item_color
	sentient_prize.tf_into(newitem, TRUE, item_name)

/obj/machinery/casinosentientprize_handler/proc/insert_chip(obj/item/spacecasinocash/cashmoney, mob/user, buystate)
	insert_chip_stage(cashmoney, user, buystate, list())

/obj/machinery/casinosentientprize_handler/proc/insert_chip_stage(obj/item/spacecasinocash/cashmoney, mob/user, buystate, list/purchase_answers)
	// Snapshot the shared instance var: it can be reassigned/nulled by another user's
	// interaction while this purchase sleeps on a dialog, so work off a stable local.
	var/obj/item/clothing/accessory/collar/casinosentientprize/collar = selected_collar
	if(QDELETED(collar))
		to_chat(user,span_notice("There is no prize selected!"))
		return
	// A still-owned collar means it's already been bought; never charge for it.
	if(collar.ownername)
		to_chat(user,span_notice("That prize has already been claimed!"))
		return

	// Snapshot the authoritative price before charging.
	var/charge = casinosentientprize_price
	if(cashmoney.worth < charge)
		to_chat(user,span_notice("You dont have enough chips to pay for the sentient prize!"))
		return

	// For the buy + item-TF path, resolve the (sleeping) confirmation BEFORE charging so
	// that aborting on a collar claimed mid-dialog costs the buyer nothing. The outcome is
	// captured here and applied after the charge.
	var/do_tf = FALSE
	var/list/tf_choice = null
	var/declined_tf = FALSE
	if(buystate == "buy" && collar.sentientprizeitemtf)
		if(!("k854" in purchase_answers))
			open_request(src, /datum/prompt/choice/casino_purchase/confirmation, PROC_REF(casino_purchase_answered), answerer = user, subject = cashmoney, buy_mode = buystate, captured = purchase_answers.Copy())
			return
		var/confirm_item_tf_claim = purchase_answers["k854"]
		if(isnull(confirm_item_tf_claim))
			return
		// Re-validate the snapshotted collar after the sleeping dialog: it may have been
		// claimed/nulled in the meantime. No charge taken yet, so we just bail.
		if(QDELETED(collar) || collar.ownername)
			to_chat(user,span_warning("That prize was claimed by someone else while you decided!"))
			return
		if(confirm_item_tf_claim == "Yes")
			if(!("k861" in purchase_answers))
				var/datum/prompt/choice/casino_purchase/item/ask = open_request(src, /datum/prompt/choice/casino_purchase/item, PROC_REF(casino_purchase_answered), answerer = user, subject = cashmoney, buy_mode = buystate, captured = purchase_answers.Copy(), choices = GLOB.item_tf_options.Copy())
				if(ask?.is_open())
					ask.purchase_opened = TRUE
				return
			var/_answer_k861 = purchase_answers["k861"]
			if(isnull(_answer_k861))
				return
			tf_choice = _answer_k861
			if(QDELETED(collar) || collar.ownername)
				to_chat(user,span_warning("That prize was claimed by someone else while you decided!"))
				return
			if(LAZYLEN(tf_choice))
				do_tf = TRUE
			else
				declined_tf = TRUE

	// All sleeping dialogs are done and the collar is re-validated — charge now.
	cashmoney.worth -= charge
	cashmoney.update_icon()

	if(cashmoney.worth <= 0)
		consume(cashmoney, user)

	if(buystate == "selfbuy")
		to_chat(user,span_notice("You put [charge] credits worth of chips into the SPASM and nullify your collar!"))
		collar.icon_state = "casinoslave"
		collar.update_icon()
		collar.name = "disabled Sentient Prize Collar: [collar.sentientprizename]"
		collar.desc = "A collar worn by sentient prizes on the Golden Goose Casino. The tag says its registered to [collar.sentientprizename], but harsh red text informs you its been disabled."
		LAZYREMOVE(sentientprizes_ckeys_list, collar.sentientprizeckey)
		collar.sentientprizeckey = null
		rel_remove(src, nameof(collar_list), collar)
		if(selected_collar == collar)
			rel_clear(src, nameof(selected_collar))

	if(buystate == "buy")
		to_chat(user,span_notice("You put [charge] credits worth of chips into the SPASM and it pings to inform you bought [collar.sentientprizename]!"))
		// Apply the item-TF outcome resolved (and paid for) above.
		if(do_tf)
			var/mob/living/sentient_prize = collar.wearer
			if(sentient_prize)
				do_item_tf(sentient_prize, tf_choice)
			else
				log_runtime(EXCEPTION("Casino sentient prize collar \"[collar]\" didn't have a living mob as its wearer and couldn't item TF!"))
				to_chat(user,span_warning("\The [src] couldn't transform your prize due to the prize's collar not being able to resolve its wearer as a living mob. Contact a coder."))
				to_chat(user,span_infoplain("Falling back to claiming your prize as normal. An admin can help transform your prize!"))
		else if(declined_tf)
			to_chat(user,span_notice("You decided to claim your prize without transformation."))
		collar.icon_state = "casinoslave_owned"
		collar.update_icon()
		collar.ownername = user.name
		collar.name =  "Sentient Prize Collar: [collar.sentientprizename] owned by [collar.ownername]!"
		collar.desc = "A collar worn by sentient prizes on the Golden Goose Casino. The tag says its registered to [collar.sentientprizename] and they are owned by [collar.ownername]."
		if(selected_collar == collar)
			rel_clear(src, nameof(selected_collar))

/obj/machinery/casinosentientprize_handler/proc/setprice(mob/living/user)
	if(user.incapacitated())
		return
	if(ishuman(user) || isrobot(user))
		open_request(src, /datum/prompt/number/casino_prize_price, PROC_REF(prize_price_answered), answerer = user)

/datum/prompt/number/casino_prize_price
	question = "Select the desired price (1-1000)"
	title = "Set Price"
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/number/casino_prize_price/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/user = answerer
	if(!istype(user) || QDELETED(user) || user.incapacitated() || !(ishuman(user) || isrobot(user)))
		return "The operator cannot set the prize price."
	if(!isnull(value) && (!isnum(value) || value < 1 || value > 1000))
		return "The prize price is invalid."

/datum/prompt/number/casino_prize_price/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default, 1000, 1, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/obj/machinery/casinosentientprize_handler/proc/prize_price_answered(datum/act/request/A)
	var/mob/living/user = A.request.answerer
	if(!A.answer)
		if(!isnull(A.request.value) && !QDELETED(user))
			if(A.request.last_error == "The prize price is invalid.")
				to_chat(user, span_notice("Invalid price."))
			SStgui.update_uis(src)
		return
	casinosentientprize_price = A.answer.value
	to_chat(user, span_notice("You set the price to [casinosentientprize_price]"))
	SStgui.update_uis(src)

/obj/structure/casino_table/roulette_table/proc/roulette_stops(result, color)
	icon_state = initial(icon_state)

	if(color=="gold") // Happy celebrations!
		visible_message(span_notice("The roulette stops spinning, the ball lands on the golden zero! Fortune favors all bets!"))
		rel_set(src, nameof(confetti_spread), new /datum/effect/effect/system/confetti_spread())
		confetti_spread.attach(src) //If somehow people start dragging roulette
		confetti_spread.start_repeatedly(confetti_strength, 1 SECOND)
	else
		visible_message(span_notice("The roulette stops spinning, the ball landing on [result], [color]."))

/// The wheel stops: the result, confetti, and the wheel is free again.
/obj/machinery/wheel_of_fortune/proc/wheel_stops(message)
	visible_message(span_notice(message))
	rel_set(src, nameof(confetti_spread), new /datum/effect/effect/system/confetti_spread())
	confetti_spread.attach(src) //If somehow people start dragging slot machine
	confetti_spread.start_repeatedly(confetti_strength, 1 SECOND)
	flick("[icon_state]-winning",src)
	icon_state = "wheel_of_fortune"

/obj/structure/casino_table/roulette_table/ownership()
	. = ..()
	. += owns(nameof(ball), policy = OWN_CONTAINED, starts = /obj/item/roulette_ball)

/obj/machinery/wheel_of_fortune/proc/wheel_use_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = wheel_use_apply(A)
	SStgui.update_uis(src)

/obj/machinery/wheel_of_fortune/proc/wheel_use_apply(datum/act/request/A)
	var/datum/prompt/choice/wheel_review/ask = A.answer
	ask.wheel_answers[ask.wheel_key] = ask.value
	return wheel_use_stage(ask.wheel_operator, ask.wheel_held, ask.wheel_interaction, ask.wheel_answers)

/obj/machinery/wheel_of_fortune/proc/wheel_management_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = wheel_management_apply(A)
	SStgui.update_uis(src)

/obj/machinery/wheel_of_fortune/proc/wheel_management_apply(datum/act/request/A)
	var/datum/prompt/choice/wheel_review/ask = A.answer
	ask.wheel_answers[ask.wheel_key] = ask.value
	return wheel_management_stage(ask.wheel_operator, ask.wheel_held, ask.wheel_interaction, ask.wheel_answers)

/obj/machinery/wheel_of_fortune/proc/wheel_interval_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = wheel_interval_apply(A)
	SStgui.update_uis(src)

/obj/machinery/wheel_of_fortune/proc/wheel_interval_apply(datum/act/request/A)
	var/datum/prompt/number/wheel_review/ask = A.answer
	ask.wheel_answers[ask.wheel_key] = ask.value
	return wheel_interval_stage(ask.wheel_operator, ask.wheel_answers)

/datum/prompt/choice/wheel_review
	timeout = 0
	var/mob/wheel_operator
	var/wheel_operator_expected = FALSE
	var/obj/item/wheel_held
	var/wheel_held_expected = FALSE
	var/datum/interaction/wheel_interaction
	var/wheel_interaction_expected = FALSE
	var/list/wheel_answers
	var/wheel_key

CAPABILITIES(/datum/prompt/choice/wheel_review)
	ref_one(nameof(wheel_operator), /mob)
	ref_one(nameof(wheel_held), /obj/item)
	ref_one(nameof(wheel_interaction), /datum/interaction)

/datum/prompt/choice/wheel_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_wheel_operator = wheel_operator
	wheel_operator_expected = !isnull(captured_wheel_operator)
	rel_clear(src, nameof(wheel_operator))
	if(captured_wheel_operator && !QDELETED(captured_wheel_operator))
		rel_set(src, nameof(wheel_operator), captured_wheel_operator)
	var/obj/item/captured_wheel_held = wheel_held
	wheel_held_expected = !isnull(captured_wheel_held)
	rel_clear(src, nameof(wheel_held))
	if(captured_wheel_held && !QDELETED(captured_wheel_held))
		rel_set(src, nameof(wheel_held), captured_wheel_held)
	var/datum/interaction/captured_wheel_interaction = wheel_interaction
	wheel_interaction_expected = !isnull(captured_wheel_interaction)
	rel_clear(src, nameof(wheel_interaction))
	if(captured_wheel_interaction && !QDELETED(captured_wheel_interaction))
		rel_set(src, nameof(wheel_interaction), captured_wheel_interaction)

/datum/prompt/choice/wheel_review/recheck_extra()
	if((wheel_operator_expected && QDELETED(wheel_operator)) || (wheel_held_expected && QDELETED(wheel_held)) || (wheel_interaction_expected && QDELETED(wheel_interaction)))
		return "gone"

/datum/prompt/number/wheel_review
	timeout = 0
	min_value = null
	max_value = null
	step = null
	var/mob/wheel_operator
	var/wheel_operator_expected = FALSE
	var/obj/item/wheel_held
	var/wheel_held_expected = FALSE
	var/datum/interaction/wheel_interaction
	var/wheel_interaction_expected = FALSE
	var/list/wheel_answers
	var/wheel_key

CAPABILITIES(/datum/prompt/number/wheel_review)
	ref_one(nameof(wheel_operator), /mob)
	ref_one(nameof(wheel_held), /obj/item)
	ref_one(nameof(wheel_interaction), /datum/interaction)

/datum/prompt/number/wheel_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_wheel_operator = wheel_operator
	wheel_operator_expected = !isnull(captured_wheel_operator)
	rel_clear(src, nameof(wheel_operator))
	if(captured_wheel_operator && !QDELETED(captured_wheel_operator))
		rel_set(src, nameof(wheel_operator), captured_wheel_operator)
	var/obj/item/captured_wheel_held = wheel_held
	wheel_held_expected = !isnull(captured_wheel_held)
	rel_clear(src, nameof(wheel_held))
	if(captured_wheel_held && !QDELETED(captured_wheel_held))
		rel_set(src, nameof(wheel_held), captured_wheel_held)
	var/datum/interaction/captured_wheel_interaction = wheel_interaction
	wheel_interaction_expected = !isnull(captured_wheel_interaction)
	rel_clear(src, nameof(wheel_interaction))
	if(captured_wheel_interaction && !QDELETED(captured_wheel_interaction))
		rel_set(src, nameof(wheel_interaction), captured_wheel_interaction)

/datum/prompt/number/wheel_review/recheck_extra()
	if((wheel_operator_expected && QDELETED(wheel_operator)) || (wheel_held_expected && QDELETED(wheel_held)) || (wheel_interaction_expected && QDELETED(wheel_interaction)))
		return "gone"

/datum/prompt/number/wheel_review/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, 1000, 1, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/choice/casino_purchase
	timeout = 0
	recheck_on_open = TRUE
	var/buy_mode
	var/answer_key
	var/purchase_opened = FALSE

/datum/prompt/choice/casino_purchase/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer) || !subject || QDELETED(subject))
		return "gone"
	return null

/datum/prompt/choice/casino_purchase/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/casino_purchase/refusal(given)
	return null

/datum/prompt/choice/casino_purchase/confirmation
	question = "This prize has opted in to being transformed into an item! Would you like to claim your prize as an item?"
	title = "Confirm Prize Item Transformation"
	buttons = TRUE
	choices = list("Yes", "No")
	answer_key = "k854"

/datum/prompt/choice/casino_purchase/item
	question = "Choose the item to claim your prize as. (Cancelling will default you to claiming your prize without transformation!)"
	title = "Choose Sentient Prize Item"
	answer_key = "k861"

/obj/machinery/casinosentientprize_handler/proc/casino_purchase_answered(datum/act/request/A)
	var/datum/prompt/choice/casino_purchase/ask = A.request
	if(!A.answer)
		// Only a genuine close of the optional item question means a normal purchase.
		if(ask.answer_key != "k861" || !ask.purchase_opened || ask.outcome != REQ_CANCELLED || !isnull(ask.value) || !isnull(request_recheck(ask)))
			return
	var/list/purchase_answers = ask.captured.Copy()
	purchase_answers[ask.answer_key] = A.answer ? A.answer.value : ""
	// Queue the original rerun completion push before the non-yielding replay, so a
	// runtime still leaves its normal presentation push scheduled.
	SStgui.update_uis(src)
	insert_chip_stage(ask.subject, ask.answerer, ask.buy_mode, purchase_answers)
