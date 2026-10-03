/datum/data/pda/app/game_launcher
	name = "Game Launcher"
	icon = "dice"
	notify_icon = "dice-d20"
	title = "Game Launcher V1.0"
	template = "pda_game_launcher"

	var/datum/board_game/vore_sweeper/voresweeper
	var/datum/board_game/four_row/fourrow
	var/datum/board_game/space_battle/spacebattle
	var/datum/board_game/rpg_dice/rpgdice
	var/datum/board_game/chess/chess
	var/datum/board_game/checkers/checkers
	var/datum/board_game/nine_mens/ninemens
	var/datum/board_game/four_row/tic_tac_toe/tictactoe

CAPABILITIES(/datum/data/pda/app/game_launcher)
	owns_one(nameof(checkers), /datum/board_game/checkers)
	owns_one(nameof(chess), /datum/board_game/chess)
	owns_one(nameof(fourrow), /datum/board_game/four_row)
	owns_one(nameof(ninemens), /datum/board_game/nine_mens)
	owns_one(nameof(rpgdice), /datum/board_game/rpg_dice)
	owns_one(nameof(spacebattle), /datum/board_game/space_battle)
	owns_one(nameof(tictactoe), /datum/board_game/four_row/tic_tac_toe)
	owns_one(nameof(voresweeper), /datum/board_game/vore_sweeper)

/datum/data/pda/app/game_launcher/update_ui(mob/user, list/data)
	data["available_games"] = list(GAME_SWEEPER = voresweeper, GAME_FOUR_ROW = fourrow, GAME_SPACE_BATTLE = spacebattle, GAME_RGP_DICE = rpgdice, GAME_CHESS = chess, GAME_CHECKERS = checkers, GAME_NINE_MENS_MORRIS = ninemens, GAME_TIC_TAC_TOE = tictactoe)

UI_ACT(/datum/data/pda/app/game_launcher, GAME_SWEEPER, ui_act_game_sweeper, UI_ARG_VALUE("close"))
UI_ACT_PROC(/datum/data/pda/app/game_launcher, ui_act_game_sweeper)
	if(params["close"])
		if(!voresweeper)
			return FALSE
		own_clear(src, nameof(/datum/data/pda/app/game_launcher::voresweeper), OWN_DELETE)
		return TRUE
	if(!voresweeper)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::voresweeper), new /datum/board_game/vore_sweeper(pda()))
	voresweeper.tgui_interact(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/game_launcher, GAME_FOUR_ROW, ui_act_game_four_row, UI_ARG_VALUE("close"))
UI_ACT_PROC(/datum/data/pda/app/game_launcher, ui_act_game_four_row)
	if(params["close"])
		if(!fourrow)
			return FALSE
		own_clear(src, nameof(/datum/data/pda/app/game_launcher::fourrow), OWN_DELETE)
		return TRUE
	if(!fourrow)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::fourrow), new /datum/board_game/four_row(pda()))
	fourrow.tgui_interact(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/game_launcher, GAME_SPACE_BATTLE, ui_act_game_space_battle, UI_ARG_VALUE("close"))
UI_ACT_PROC(/datum/data/pda/app/game_launcher, ui_act_game_space_battle)
	if(params["close"])
		if(!spacebattle)
			return FALSE
		own_clear(src, nameof(/datum/data/pda/app/game_launcher::spacebattle), OWN_DELETE)
		return TRUE
	if(!spacebattle)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::spacebattle), new /datum/board_game/space_battle(pda()))
	spacebattle.tgui_interact(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/game_launcher, GAME_RGP_DICE, ui_act_game_rgp_dice, UI_ARG_VALUE("close"))
UI_ACT_PROC(/datum/data/pda/app/game_launcher, ui_act_game_rgp_dice)
	if(params["close"])
		if(!rpgdice)
			return FALSE
		own_clear(src, nameof(/datum/data/pda/app/game_launcher::rpgdice), OWN_DELETE)
		return TRUE
	if(!rpgdice)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::rpgdice), new /datum/board_game/rpg_dice(pda()))
	rpgdice.tgui_interact(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/game_launcher, GAME_CHESS, ui_act_game_chess, UI_ARG_VALUE("close"))
UI_ACT_PROC(/datum/data/pda/app/game_launcher, ui_act_game_chess)
	if(params["close"])
		if(!chess)
			return FALSE
		own_clear(src, nameof(/datum/data/pda/app/game_launcher::chess), OWN_DELETE)
		return TRUE
	if(!chess)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::chess), new /datum/board_game/chess(pda()))
	chess.tgui_interact(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/game_launcher, GAME_CHECKERS, ui_act_game_checkers, UI_ARG_VALUE("close"))
UI_ACT_PROC(/datum/data/pda/app/game_launcher, ui_act_game_checkers)
	if(params["close"])
		if(!checkers)
			return FALSE
		own_clear(src, nameof(/datum/data/pda/app/game_launcher::checkers), OWN_DELETE)
		return TRUE
	if(!checkers)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::checkers), new /datum/board_game/checkers(pda()))
	checkers.tgui_interact(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/game_launcher, GAME_NINE_MENS_MORRIS, ui_act_game_nine_mens_morris, UI_ARG_VALUE("close"))
UI_ACT_PROC(/datum/data/pda/app/game_launcher, ui_act_game_nine_mens_morris)
	if(params["close"])
		if(!ninemens)
			return FALSE
		own_clear(src, nameof(/datum/data/pda/app/game_launcher::ninemens), OWN_DELETE)
		return TRUE
	if(!ninemens)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::ninemens), new /datum/board_game/nine_mens(pda()))
	ninemens.tgui_interact(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/game_launcher, GAME_TIC_TAC_TOE, ui_act_game_tic_tac_toe, UI_ARG_VALUE("close"))
UI_ACT_PROC(/datum/data/pda/app/game_launcher, ui_act_game_tic_tac_toe)
	if(params["close"])
		if(!tictactoe)
			return FALSE
		own_clear(src, nameof(/datum/data/pda/app/game_launcher::tictactoe), OWN_DELETE)
		return TRUE
	if(!tictactoe)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::tictactoe), new /datum/board_game/four_row/tic_tac_toe(pda()))
	tictactoe.tgui_interact(ui.user)
	return TRUE

