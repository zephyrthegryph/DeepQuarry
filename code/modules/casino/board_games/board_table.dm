/obj/structure/casino_table/board_game
	name = "board game table"
	desc = "A collection of various board games."
	icon_state = "gamble_preview"
	var/datum/board_game/game_ui
	var/static/list/possible_games = list(
		GAME_SWEEPER = /datum/board_game/vore_sweeper,
		GAME_FOUR_ROW = /datum/board_game/four_row,
		GAME_SPACE_BATTLE = /datum/board_game/space_battle,
		GAME_RGP_DICE = /datum/board_game/rpg_dice,
		GAME_CHESS = /datum/board_game/chess,
		GAME_CHECKERS = /datum/board_game/checkers,
		GAME_NINE_MENS_MORRIS = /datum/board_game/nine_mens,
		GAME_TIC_TAC_TOE = /datum/board_game/four_row/tic_tac_toe
	)

/obj/structure/casino_table/board_game/Initialize(mapload)
	. = ..()
	if(ispath(game_ui))
		game_ui = new game_ui(src)

DECLARE_REF(/obj/structure/casino_table/board_game, "game_ui", OWNED, null)

EXTEND_INTERACTIONS(/obj/structure/casino_table/board_game, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
)

/// Old attack_hand.
/obj/structure/casino_table/board_game/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(isliving(user))
		if(!game_ui)
			pick_game(user)
		if(game_ui)
			game_ui.tgui_interact(user)
	return TRUE

/// Old click_alt.
/obj/structure/casino_table/board_game/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	pick_game(user)
	return TRUE

/obj/structure/casino_table/board_game/proc/pick_game(mob/user)
	if(game_ui?.game_state != GAME_SETUP)
		return
	var/datum/board_game/new_game = rerun_ask(user, "k42", PROC_REF(pick_game), args, /datum/om/prompt/choice, message = "Pick the game to play", title = "Choose Game", choices = possible_games)
	if(isnull(new_game))
		return
	if(!new_game)
		return
	new_game = possible_games[new_game]
	if(game_ui)
		QDEL_NULL(game_ui)
	game_ui = new new_game(src)
	icon_state = game_ui.table_icon

/datum/board_game
	var/name
	var/tmp/parent_handle
	var/game_state = GAME_SETUP
	var/table_icon = "gamble_preview"

/datum/board_game/tgui_state(mob/user)
	return GLOB.tgui_board_game_state

/datum/board_game/New(atom/holder)
	. = ..()
	parent_handle = om_handle(holder)

/datum/board_game/tgui_host(mob/user)
	return parent()

/datum/board_game/tgui_act(action, list/params, datum/tgui/ui, datum/tgui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("invite_player")
			var/list/possible_mobs = ui.user.living_mobs_in_view(1, TRUE, TRUE)
			for(var/obj/belly/our_belly in ui.user.vore_organs)
				for(var/mob/living/prey in contents_of(our_belly))
					if(prey.client)
						possible_mobs += prey
			var/mob/living/new_player = act_ask(ui.user, action, params, ui, "k83", /datum/om/prompt/choice, message = "Invite a nearby player to the game.", title = "Invite Player", choices = possible_mobs)
			if(isnull(new_player))
				return
			if(!new_player)
				return FALSE
			tgui_interact(new_player)
			return TRUE
	return FALSE

/// LC-refs: the parent this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/board_game/proc/parent() as /atom
	return om_resolve(parent_handle)
