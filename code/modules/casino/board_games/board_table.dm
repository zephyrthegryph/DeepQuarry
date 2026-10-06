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

CAPABILITIES(/obj/structure/casino_table/board_game)
	owns_one(nameof(game_ui), /datum/board_game, starts = nameof(game_ui))


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
	var/datum/board_game/new_game = rerun_ask(user, "k42", PROC_REF(pick_game), args, /datum/prompt/choice, question = "Pick the game to play", title = "Choose Game", choices = possible_games)
	if(isnull(new_game))
		return
	if(!new_game)
		return
	new_game = possible_games[new_game]
	if(game_ui)
		own_clear(src, nameof(game_ui), OWN_DELETE)
	rel_set(src, nameof(game_ui), new new_game(src))
	icon_state = game_ui.table_icon

/datum/board_game
	var/name
	var/tmp/atom/parent
	var/game_state = GAME_SETUP
	var/table_icon = "gamble_preview"

CAPABILITIES(/datum/board_game)
	op("invite_player", ui_act("invite_player"), asks(/datum/prompt/choice, fields = list("question" = "Invite a nearby player to the game.", "title" = "Invite Player", "choices" = computed(PROC_REF(invitable_players)), "timeout" = 0), step = "k83"), then(PROC_REF(ui_act_invite_player)))

/datum/board_game/New(atom/holder)
	. = ..()
	rel_set(src, nameof(parent), holder)

/datum/board_game/tgui_host(mob/user)
	return parent()

/datum/board_game/proc/ui_act_invite_player(datum/act/op/A)
	var/mob/living/new_player = A.step_value("k83")
	if(!istype(new_player))
		return FALSE
	tgui_interact(new_player)
	return TRUE

/// The players the inviter can see (or holds in a belly), offered by the invite question.
/datum/board_game/proc/invitable_players(datum/act/op/A)
	var/mob/user = A.actor
	var/list/possible_mobs = user.living_mobs_in_view(1, TRUE, TRUE)
	for(var/obj/belly/our_belly in user.vore_organs)
		for(var/mob/living/prey in contents_of(our_belly))
			if(prey.client)
				possible_mobs += prey
	return possible_mobs

/// The game's sub-actions (a move and its data, sent inside "game_action"): each game routes its own; null for one it has not.
/datum/board_game/proc/game_subaction(action, list/data, mob/user, extra)
	return null

/// The setup sub-actions (sent inside "setup_action"), routed the same way.
/datum/board_game/proc/setup_subaction(action, list/data, mob/user, extra)
	return null

/// The table this game sits on (a relation view: null once it is deleted).
/datum/board_game/proc/parent() as /atom
	return parent
