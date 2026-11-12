CAPABILITIES(/datum/board_game/rpg_dice)
	op("clear_history", ui_act(), then(PROC_REF(ui_act_clear_history)))
	interface("RpgDice", state = nameof(GLOB.tgui_board_game_state))
	ui_shape(last_rolls = list_of(row(player = schema_text(), count = int(), size = int(), results = list_of(row(result = int(), state = int())), mod = num(), apply_to_all = bool(), sum = num())))
	// The quick dice buttons send only dice_size; the roller panel sends all four.
	op("roll_dice", ui_act("roll_dice", arg("dice_count", num(), optional = TRUE), arg("dice_mod", num(), optional = TRUE), arg("dice_size", num()), arg("mod_all", bool(), optional = TRUE)), then(PROC_REF(ui_act_roll_dice)))
	// The text box: "2d6+3", "d20", "4d8-1".
	op("custom_roll", ui_act("custom_roll", arg("custom", schema_text(64))), needs(req(PROC_REF(custom_roll_refusal))), then(PROC_REF(ui_act_custom_roll)))

/obj/structure/casino_table/board_game/rpg_dice
	name = GAME_RGP_DICE
	desc = "A set of dice to roll with your friends."
	icon_state = "gamble_dice"
	game_ui = /datum/board_game/rpg_dice

/datum/board_game/rpg_dice
	name = GAME_RGP_DICE
	table_icon = "gamble_dice"
	var/list/last_rolls

/// /datum/board_game/rpg_dice's window data.
/datum/board_game/rpg_dice/ui_data(datum/act/eval/A)
	return list(
		"last_rolls" = (last_rolls || list()),
	)

/datum/board_game/rpg_dice/proc/ui_act_roll_dice(datum/act/op/A, dice_count_arg, dice_mod, dice_size_arg, mod_all)
	var/mob/user = A.actor
	var/dice_size = dice_size_arg
	if(!isnum(dice_size) || dice_size > 10000)
		return FALSE
	var/dice_count = dice_count_arg
	if(!isnum(dice_count) || dice_count < 1 || dice_count > 10)
		dice_count = 1
	var/modifier = dice_mod
	var/list/results = list()
	var/sum = 0
	if(!isnum(modifier))
		modifier = 0
	var/apply_to_all = mod_all
	for(var/dice in 1 to dice_count)
		var/result = rand(1, dice_size)
		UNTYPED_LIST_ADD(results, list("result" = result, "state" = check_crit(1, dice_size, result)))
		sum += result
	sum += apply_to_all ? modifier * dice_count : modifier
	UNTYPED_LIST_ADD(last_rolls, list("player" = user, "count" = dice_count, "size" = dice_size, "results" = results, "mod" = modifier, "apply_to_all" = apply_to_all, "sum" = sum))
	return TRUE

/// A typed roll, "NdS", "NdS+M" or "NdS-M" (N defaults to 1): rolled like the roller panel's dice.
/datum/board_game/rpg_dice/proc/ui_act_custom_roll(datum/act/op/A, custom)
	var/list/roll = parse_roll(custom)
	return ui_act_roll_dice(A, roll[1], roll[3], roll[2], FALSE)

/// Why the typed roll can't be made, or null.
/datum/board_game/rpg_dice/proc/custom_roll_refusal(datum/act/op/A)
	return parse_roll(A.args["custom"]) ? null : msg_reason("Write a roll like 2d6+3.")

/// The typed roll as list(count, size, modifier), or null when it isn't a roll.
/datum/board_game/rpg_dice/proc/parse_roll(custom)
	var/static/regex/dice_text = regex(@"^\s*(\d*)\s*[dD]\s*(\d+)\s*(?:([+-])\s*(\d+))?\s*$")
	if(!istext(custom) || !dice_text.Find(custom))
		return null
	var/count = length(dice_text.group[1]) ? text2num(dice_text.group[1]) : 1
	var/size = text2num(dice_text.group[2])
	var/mod = length(dice_text.group[4]) ? text2num(dice_text.group[4]) : 0
	if(dice_text.group[3] == "-")
		mod = -mod
	if(size < 1)
		return null
	return list(count, size, mod)

/datum/board_game/rpg_dice/proc/ui_act_clear_history(datum/act/op/A)
	clear_last_rolls()
	return OP_OK

/datum/board_game/rpg_dice/proc/check_crit(low, max, result)
	if(result == low)
		return 1
	if(result == max)
		return 2
	return 0
