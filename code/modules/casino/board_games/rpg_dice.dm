/obj/structure/casino_table/board_game/rpg_dice
	name = GAME_RGP_DICE
	desc = "A set of dice to roll with your friends."
	icon_state = "gamble_dice"
	game_ui = /datum/board_game/rpg_dice

/datum/board_game/rpg_dice
	name = GAME_RGP_DICE
	table_icon = "gamble_dice"
	var/list/last_rolls

DECLARE_UI(/datum/board_game/rpg_dice, "RpgDice")

/datum/board_game/rpg_dice/tgui_data(mob/user, datum/tgui/ui, datum/tgui_state/state)
	return list(
		"last_rolls" = (last_rolls || list()),
	)

UI_ACT(/datum/board_game/rpg_dice, "roll_dice", ui_act_roll_dice, UI_ARG_NUM("dice_count"), UI_ARG_NUM("dice_mod"), UI_ARG_NUM("dice_size"), UI_ARG_VALUE("mod_all"))
UI_ACT_PROC(/datum/board_game/rpg_dice, ui_act_roll_dice)
	var/dice_size = params["dice_size"]
	if(!isnum(dice_size) || dice_size > 10000)
		return FALSE
	var/dice_count = params["dice_count"]
	if(!isnum(dice_count) || dice_count < 1 || dice_count > 10)
		dice_count = 1
	var/modifier = params["dice_mod"]
	var/list/results = list()
	var/sum = 0
	if(!isnum(modifier))
		modifier = 0
	var/apply_to_all = params["mod_all"]
	for(var/dice in 1 to dice_count)
		var/result = rand(1, dice_size)
		UNTYPED_LIST_ADD(results, list("result" = result, "state" = check_crit(1, dice_size, result)))
		sum += result
	sum += apply_to_all ? modifier * dice_count : modifier
	UNTYPED_LIST_ADD(last_rolls, list("player" = ui.user, "count" = dice_count, "size" = dice_size, "results" = results, "mod" = modifier, "apply_to_all" = apply_to_all, "sum" = sum))
	return TRUE

UI_ACT(/datum/board_game/rpg_dice, "clear_history", ui_act_clear_history)
UI_ACT_PROC(/datum/board_game/rpg_dice, ui_act_clear_history)
	LAZYCLEARLIST(last_rolls)
	return TRUE

/datum/board_game/rpg_dice/proc/check_crit(low, max, result)
	if(result == low)
		return 1
	if(result == max)
		return 2
	return 0
