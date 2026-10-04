
ADMIN_VERB(roll_dices, R_FUN, "Roll Dice", "Allows to roll a dice.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	return advance_dice(user)

/datum/admin_verb/roll_dices/proc/dice_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/next_stage
	var/sum
	var/side
	var/show_game
	if(istype(A.request, /datum/prompt/number/admin_dice))
		var/datum/prompt/number/admin_dice/ask = A.request
		next_stage = ask.next_stage
		sum = next_stage == 1 ? ask.answer_value : ask.sum
		side = next_stage == 2 ? ask.answer_value : null
	else
		var/datum/prompt/choice/admin_dice/ask = A.request
		next_stage = ask.next_stage
		sum = ask.sum
		side = ask.side
		show_game = next_stage == 3 ? ask.answer_value : ask.show_game
	var/datum/result/result = safe_call(PROC_REF(advance_dice), A.request.answerer.client, next_stage, sum, side, show_game, A.request.answer_value)
	if(!result.ok)
		stack_trace("om flow roll_dices answer dice_answered: [result.error]")

/datum/admin_verb/roll_dices/proc/advance_dice(client/user, stage = 0, sum = null, side = null, show_game = null, show_result = null)
	var/mob/answerer = user.mob
	if(QDELETED(answerer))
		return
	if(stage == 0)
		open_request(src, /datum/prompt/number/admin_dice, PROC_REF(dice_answered), answerer = answerer, question = "How many times should we throw?", next_stage = 1)
		return
	if(stage == 1)
		open_request(src, /datum/prompt/number/admin_dice, PROC_REF(dice_answered), answerer = answerer, question = "Select the number of sides.", next_stage = 2, sum = sum)
		return
	if(stage == 2)
		open_request(src, /datum/prompt/choice/admin_dice, PROC_REF(dice_answered), answerer = answerer, question = "Do you want to inform the world about your game?", next_stage = 3, sum = sum, side = side)
		return
	if(stage == 3)
		open_request(src, /datum/prompt/choice/admin_dice, PROC_REF(dice_answered), answerer = answerer, question = "Do you want to inform the world about the result?", next_stage = 4, sum = sum, side = side, show_game = show_game)
		return
	if(!side)
		side = 6
	if(!sum)
		sum = 2

	var/dice = num2text(sum) + "d" + num2text(side)

	if(show_game == "Yes")
		to_chat(world, "<h2 style=\"color:#A50400\">The dice have been rolled by Gods!</h2>")

	var/result = roll(dice)

	if(show_result == "Yes")
		to_chat(world, "<h2 style=\"color:#A50400\">Gods rolled [dice], result is [result]</h2>")

	message_admins("[key_name_admin(user)] rolled dice [dice], result is [result]", 1)

/datum/prompt/number/admin_dice
	rights = R_FUN
	timeout = 0
	min_value = 0
	max_value = INFINITY
	step = 1
	var/next_stage
	var/sum

/datum/prompt/number/admin_dice/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/number/admin_dice/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default, isnull(max_value) ? INFINITY : max_value, isnull(min_value) ? 0 : min_value, timeout, !isnull(step), GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/choice/admin_dice
	rights = R_FUN
	timeout = 0
	title = "Show world?"
	buttons = TRUE
	choices = list("Yes", "No")
	var/next_stage
	var/sum
	var/side
	var/show_game

/datum/prompt/choice/admin_dice/begin()
	if(request_recheck(src))
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()
