
ADMIN_VERB(roll_dices, R_FUN, "Roll Dice", "Allows to roll a dice.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	// Everything is asked first; the roll happens once, after the last answer.
	var/sum = verb_prompt(user, "sum", list("kind" = "number", "message" = "How many times should we throw?"), args)
	if(isnull(sum))
		return
	var/side = verb_prompt(user, "side", list("kind" = "number", "message" = "Select the number of sides."), args)
	if(isnull(side))
		return
	var/show_game = verb_prompt(user, "show_game", list("message" = "Do you want to inform the world about your game?", "title" = "Show world?", "choices" = list("Yes", "No")), args)
	if(isnull(show_game))
		return
	var/show_result = verb_prompt(user, "show_result", list("message" = "Do you want to inform the world about the result?", "title" = "Show world?", "choices" = list("Yes", "No")), args)
	if(isnull(show_result))
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
