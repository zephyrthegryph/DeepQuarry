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
	op(GAME_SWEEPER, ui_act(GAME_SWEEPER, arg("close")), then(PROC_REF(ui_act_game_sweeper)))
	op(GAME_FOUR_ROW, ui_act(GAME_FOUR_ROW, arg("close")), then(PROC_REF(ui_act_game_four_row)))
	op(GAME_SPACE_BATTLE, ui_act(GAME_SPACE_BATTLE, arg("close")), then(PROC_REF(ui_act_game_space_battle)))
	op(GAME_RGP_DICE, ui_act(GAME_RGP_DICE, arg("close")), then(PROC_REF(ui_act_game_rgp_dice)))
	op(GAME_CHESS, ui_act(GAME_CHESS, arg("close")), then(PROC_REF(ui_act_game_chess)))
	op(GAME_CHECKERS, ui_act(GAME_CHECKERS, arg("close")), then(PROC_REF(ui_act_game_checkers)))
	op(GAME_NINE_MENS_MORRIS, ui_act(GAME_NINE_MENS_MORRIS, arg("close")), then(PROC_REF(ui_act_game_nine_mens_morris)))
	op(GAME_TIC_TAC_TOE, ui_act(GAME_TIC_TAC_TOE, arg("close")), then(PROC_REF(ui_act_game_tic_tac_toe)))

/datum/data/pda/app/game_launcher/update_ui(mob/user, list/data)
	data["available_games"] = list(GAME_SWEEPER = voresweeper, GAME_FOUR_ROW = fourrow, GAME_SPACE_BATTLE = spacebattle, GAME_RGP_DICE = rpgdice, GAME_CHESS = chess, GAME_CHECKERS = checkers, GAME_NINE_MENS_MORRIS = ninemens, GAME_TIC_TAC_TOE = tictactoe)

/datum/data/pda/app/game_launcher/proc/ui_act_game_sweeper(datum/act/op/A, close)
	var/mob/user = A.actor
	if(close)
		if(!voresweeper)
			return FALSE
		rel_clear(src, nameof(/datum/data/pda/app/game_launcher::voresweeper))
		return TRUE
	if(!voresweeper)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::voresweeper), new /datum/board_game/vore_sweeper(pda()))
	voresweeper.tgui_interact(user)
	return TRUE

/datum/data/pda/app/game_launcher/proc/ui_act_game_four_row(datum/act/op/A, close)
	var/mob/user = A.actor
	if(close)
		if(!fourrow)
			return FALSE
		rel_clear(src, nameof(/datum/data/pda/app/game_launcher::fourrow))
		return TRUE
	if(!fourrow)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::fourrow), new /datum/board_game/four_row(pda()))
	fourrow.tgui_interact(user)
	return TRUE

/datum/data/pda/app/game_launcher/proc/ui_act_game_space_battle(datum/act/op/A, close)
	var/mob/user = A.actor
	if(close)
		if(!spacebattle)
			return FALSE
		rel_clear(src, nameof(/datum/data/pda/app/game_launcher::spacebattle))
		return TRUE
	if(!spacebattle)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::spacebattle), new /datum/board_game/space_battle(pda()))
	spacebattle.tgui_interact(user)
	return TRUE

/datum/data/pda/app/game_launcher/proc/ui_act_game_rgp_dice(datum/act/op/A, close)
	var/mob/user = A.actor
	if(close)
		if(!rpgdice)
			return FALSE
		rel_clear(src, nameof(/datum/data/pda/app/game_launcher::rpgdice))
		return TRUE
	if(!rpgdice)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::rpgdice), new /datum/board_game/rpg_dice(pda()))
	rpgdice.tgui_interact(user)
	return TRUE

/datum/data/pda/app/game_launcher/proc/ui_act_game_chess(datum/act/op/A, close)
	var/mob/user = A.actor
	if(close)
		if(!chess)
			return FALSE
		rel_clear(src, nameof(/datum/data/pda/app/game_launcher::chess))
		return TRUE
	if(!chess)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::chess), new /datum/board_game/chess(pda()))
	chess.tgui_interact(user)
	return TRUE

/datum/data/pda/app/game_launcher/proc/ui_act_game_checkers(datum/act/op/A, close)
	var/mob/user = A.actor
	if(close)
		if(!checkers)
			return FALSE
		rel_clear(src, nameof(/datum/data/pda/app/game_launcher::checkers))
		return TRUE
	if(!checkers)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::checkers), new /datum/board_game/checkers(pda()))
	checkers.tgui_interact(user)
	return TRUE

/datum/data/pda/app/game_launcher/proc/ui_act_game_nine_mens_morris(datum/act/op/A, close)
	var/mob/user = A.actor
	if(close)
		if(!ninemens)
			return FALSE
		rel_clear(src, nameof(/datum/data/pda/app/game_launcher::ninemens))
		return TRUE
	if(!ninemens)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::ninemens), new /datum/board_game/nine_mens(pda()))
	ninemens.tgui_interact(user)
	return TRUE

/datum/data/pda/app/game_launcher/proc/ui_act_game_tic_tac_toe(datum/act/op/A, close)
	var/mob/user = A.actor
	if(close)
		if(!tictactoe)
			return FALSE
		rel_clear(src, nameof(/datum/data/pda/app/game_launcher::tictactoe))
		return TRUE
	if(!tictactoe)
		rel_set(src, nameof(/datum/data/pda/app/game_launcher::tictactoe), new /datum/board_game/four_row/tic_tac_toe(pda()))
	tictactoe.tgui_interact(user)
	return TRUE

