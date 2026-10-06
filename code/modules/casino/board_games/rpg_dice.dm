CAPABILITIES(/datum/board_game/rpg_dice)
	op("clear_history", ui_act(), then(PROC_REF(ui_act_clear_history)))
	interface("RpgDice", state = nameof(GLOB.tgui_board_game_state))
	op("roll_dice", ui_act("roll_dice", arg("dice_count", num()), arg("dice_mod", num()), arg("dice_size", num()), arg("mod_all", bool())), then(PROC_REF(ui_act_roll_dice)))

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

/datum/board_game/rpg_dice/proc/ui_act_clear_history(datum/act/op/A)
	LAZYCLEARLIST(last_rolls)
	return OP_OK

/datum/board_game/rpg_dice/proc/check_crit(low, max, result)
	if(result == low)
		return 1
	if(result == max)
		return 2
	return 0
