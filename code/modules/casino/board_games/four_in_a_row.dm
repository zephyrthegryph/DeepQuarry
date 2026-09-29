#define GAME_PLAYER_ONE 1
#define GAME_PLAYER_TWO 2
#define GAME_OVER 3
#define GAME_OVER_DRAW 4

/obj/structure/casino_table/board_game/four_row
	name = GAME_FOUR_ROW
	desc = "A game where two players need to connect their chips in a row."
	icon_state = "gamble_four"
	game_ui = /datum/board_game/four_row

/datum/board_game/four_row
	name = GAME_FOUR_ROW
	table_icon = "gamble_four"
	var/mob/player_one
	var/mob/player_two
	var/list/placed_chips_pone
	var/list/placed_chips_ptwo
	var/list/winning_tiles
	var/grid_x_size = 7
	var/grid_y_size = 6
	var/win_count = 4
	var/player_one_color = "yellow"
	var/player_two_color = "red"
	var/winner
	var/static/list/possible_colors = list("red", "yellow", "green", "orange", "blue", "cyan")

DECLARE_UI(/datum/board_game/four_row, "FourInARow")

/datum/board_game/four_row/tgui_static_data(mob/user)
	return list(
		"colors" = possible_colors
	)

UI_DATA_REPLACE(/datum/board_game/four_row, "merge:ui_data_datum_board_game_four_row{player_one:unknown,player_two:unknown,placed_chips_pone:bool,placed_chips_ptwo:bool,game_state:unknown,grid_x_size:num,grid_y_size:num,player_one_color:text,player_two_color:text,win_count:num,winner:unknown,has_won:bool,winning_tiles:bool}")

/// The computed part of /datum/board_game/four_row's window data (declared on its UI_DATA row).
/datum/board_game/four_row/proc/ui_data_datum_board_game_four_row(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/mob/player_one_mob = player_one
	var/mob/player_two_mob = player_two

	return list(
		"player_one" = player_one_mob,
		"player_two" = player_two_mob,
		"placed_chips_pone" = (placed_chips_pone || list()),
		"placed_chips_ptwo" = (placed_chips_ptwo || list()),
		"game_state" = game_state,
		"grid_x_size" = grid_x_size,
		"grid_y_size" = grid_y_size,
		"player_one_color" = player_one_color,
		"player_two_color" = player_two_color,
		"win_count" = win_count,
		"winner" = winner,
		"has_won" = winner == ui.user.name,
		"winning_tiles" = (winning_tiles || list()),
	)

UI_ACT(/datum/board_game/four_row, "be_player_one", ui_act_be_player_one)
UI_ACT_PROC(/datum/board_game/four_row, ui_act_be_player_one)
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_one == ui.user)
		rel_clear(src, "player_one")
		return TRUE
	rel_set(src, "player_one", ui.user)
	return TRUE

UI_ACT(/datum/board_game/four_row, "be_player_two", ui_act_be_player_two)
UI_ACT_PROC(/datum/board_game/four_row, ui_act_be_player_two)
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_two == ui.user)
		rel_clear(src, "player_two")
		return TRUE
	rel_set(src, "player_two", ui.user)
	return TRUE

UI_ACT(/datum/board_game/four_row, "swap_players", ui_act_swap_players)
UI_ACT_PROC(/datum/board_game/four_row, ui_act_swap_players)
	if(game_state != GAME_SETUP)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	var/mob/temp_player = player_one
	rel_set(src, "player_one", player_two)
	rel_set(src, "player_two", temp_player)

UI_ACT(/datum/board_game/four_row, "set_color_one", ui_act_set_color_one, UI_ARG_VALUE("color"))
UI_ACT_PROC(/datum/board_game/four_row, ui_act_set_color_one)
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_one != ui.user)
		return FALSE
	var/new_color = params["color"]
	if(new_color == player_two_color)
		return FALSE
	if(!(new_color in possible_colors))
		return FALSE
	player_one_color = new_color
	return TRUE

UI_ACT(/datum/board_game/four_row, "set_color_two", ui_act_set_color_two, UI_ARG_VALUE("color"))
UI_ACT_PROC(/datum/board_game/four_row, ui_act_set_color_two)
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_two != ui.user)
		return FALSE
	var/new_color = params["color"]
	if(new_color == player_one_color)
		return FALSE
	if(!(new_color in possible_colors))
		return FALSE
	player_two_color = new_color
	return TRUE

UI_ACT(/datum/board_game/four_row, "change_size", ui_act_change_size, UI_ARG_NUM("size"))
UI_ACT_PROC(/datum/board_game/four_row, ui_act_change_size)
	if(game_state != GAME_SETUP)
		return FALSE
	var/new_size = params["size"]
	return set_new_size(new_size)

UI_ACT(/datum/board_game/four_row, "change_win", ui_act_change_win, UI_ARG_NUM("count"))
UI_ACT_PROC(/datum/board_game/four_row, ui_act_change_win)
	if(game_state != GAME_SETUP)
		return FALSE
	return change_win_count(params["count"])

UI_ACT(/datum/board_game/four_row, "clear_game", ui_act_clear_game)
UI_ACT_PROC(/datum/board_game/four_row, ui_act_clear_game)
	if(game_state == GAME_SETUP)
		return FALSE
	reset(TRUE)
	return TRUE

UI_ACT(/datum/board_game/four_row, "start_game", ui_act_start_game)
UI_ACT_PROC(/datum/board_game/four_row, ui_act_start_game)
	if(game_state != GAME_SETUP)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	game_state = GAME_PLAYER_ONE
	return TRUE

UI_ACT(/datum/board_game/four_row, "play_again", ui_act_play_again)
UI_ACT_PROC(/datum/board_game/four_row, ui_act_play_again)
	if(game_state < GAME_OVER)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	reset()
	return TRUE

UI_ACT(/datum/board_game/four_row, "play_again_swapped", ui_act_play_again_swapped)
UI_ACT_PROC(/datum/board_game/four_row, ui_act_play_again_swapped)
	if(game_state < GAME_OVER)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	reset()
	var/mob/temp_player = player_one
	rel_set(src, "player_one", player_two)
	rel_set(src, "player_two", temp_player)
	return TRUE

UI_ACT(/datum/board_game/four_row, "game_action", ui_act_game_action, UI_ARG_TEXT("action", 64), UI_ARG_LIST("data"))
UI_ACT_PROC(/datum/board_game/four_row, ui_act_game_action)
	if(ui.user == player_one && game_state == GAME_PLAYER_ONE)
		if(ui_subdispatch(src, "game", params["action"], params["data"], ui.user, ui, state))
			if(game_state < GAME_OVER)
				game_state = GAME_PLAYER_TWO
			return TRUE
	if(ui.user == player_two && game_state == GAME_PLAYER_TWO)
		if(ui_subdispatch(src, "game", params["action"], params["data"], ui.user, ui, state))
			if(game_state < GAME_OVER)
				game_state = GAME_PLAYER_ONE
			return TRUE
	return FALSE

/datum/board_game/four_row/proc/change_win_count(new_count)
	if(!isnum(new_count))
		return FALSE
	if(new_count < 4 || new_count > 5)
		return FALSE
	win_count = new_count
	return TRUE

/datum/board_game/four_row/proc/reset(full)
	LAZYCLEARLIST(placed_chips_pone)
	LAZYCLEARLIST(placed_chips_ptwo)
	LAZYCLEARLIST(winning_tiles)
	winner = null
	if(full)
		game_state = GAME_SETUP
		rel_clear(src, "player_one")
		rel_clear(src, "player_two")
	else
		game_state = GAME_PLAYER_ONE

UI_SUBACT(/datum/board_game/four_row, "game", "place_chip", game_place_chip, UI_ARG_NUM("loc_x"), UI_ARG_NUM("loc_y"))
UI_SUBACT_PROC(/datum/board_game/four_row, game_place_chip)
	var/list/validated_data = validate_coords(params["loc_x"], params["loc_y"])
	if(!validated_data)
		return FALSE
	var/x_loc = validated_data[2]

	var/target_y = 0
	for(var/y = grid_y_size; y >= 1; y--)
		var/key = "[x_loc],[y]"
		if(!LAZYACCESS(placed_chips_pone, key) && !LAZYACCESS(placed_chips_ptwo, key))
			target_y = y
			break

	if(target_y == 0)
		return FALSE

	var/key = "[x_loc],[target_y]"

	if(game_state == GAME_PLAYER_ONE)
		LAZYSET(placed_chips_pone, key, TRUE)
	else
		LAZYSET(placed_chips_ptwo, key, TRUE)

	validate_victory(x_loc, target_y, user.name)
	return TRUE

/datum/board_game/four_row/proc/has_chip(list/player_list, x, y)
	return player_list["[x],[y]"]

/datum/board_game/four_row/proc/collect_direction(list/player_list, start_x, start_y, dx, dy)
	var/list/tiles = list()
	var/x = start_x
	var/y = start_y

	while(field_check(x, y) && has_chip(player_list, x, y))
		tiles += "[x],[y]"
		x += dx
		y += dy

	return tiles

/datum/board_game/four_row/proc/validate_victory(x, y, user_name)
	var/list/current_list

	if(game_state == GAME_PLAYER_ONE)
		current_list = placed_chips_pone || list()
	else
		current_list = placed_chips_ptwo || list()

	var/list/h1 = collect_direction(current_list, x, y, 1, 0)
	var/list/h2 = collect_direction(current_list, x, y, -1, 0)
	var/list/horizontal = h1 + h2
	horizontal -= "[x],[y]"

	if(length(horizontal) >= win_count)
		winning_tiles = horizontal
		game_state = GAME_OVER
		winner = user_name
		return

	var/list/v1 = collect_direction(current_list, x, y, 0, 1)
	var/list/v2 = collect_direction(current_list, x, y, 0, -1)
	var/list/vertical = v1 + v2
	vertical -= "[x],[y]"

	if(length(vertical) >= win_count)
		winning_tiles = vertical
		game_state = GAME_OVER
		winner = user_name
		return

	var/list/d1 = collect_direction(current_list, x, y, 1, 1)
	var/list/d2 = collect_direction(current_list, x, y, -1, -1)
	var/list/diag1 = d1 + d2
	diag1 -= "[x],[y]"

	if(length(diag1) >= win_count)
		winning_tiles = diag1
		game_state = GAME_OVER
		winner = user_name
		return

	var/list/d3 = collect_direction(current_list, x, y, 1, -1)
	var/list/d4 = collect_direction(current_list, x, y, -1, 1)
	var/list/diag2 = d3 + d4
	diag2 -= "[x],[y]"

	if(length(diag2) >= win_count)
		winning_tiles = diag2
		game_state = GAME_OVER
		winner = user_name
		return
	check_draw()

/datum/board_game/four_row/proc/check_draw()
	for(var/x = 1 to grid_x_size)
		for(var/y = 1 to grid_y_size)
			var/key = "[x],[y]"
			if(!LAZYACCESS(placed_chips_pone, key) && !LAZYACCESS(placed_chips_ptwo, key))
				return FALSE

	winner = null
	game_state = GAME_OVER_DRAW
	return TRUE

/datum/board_game/four_row/proc/set_new_size(new_size)
	if(!isnum(new_size))
		return FALSE
	if(new_size < 5 || new_size > 10)
		return FALSE
	grid_x_size = new_size
	grid_y_size = new_size - 1
	return TRUE

/datum/board_game/four_row/proc/field_check(new_x_location, new_y_location)
	if(new_x_location < 1 || new_x_location > grid_x_size)
		return FALSE
	if(new_y_location < 1 || new_y_location > grid_y_size)
		return FALSE
	return TRUE

/datum/board_game/four_row/proc/validate_coords(x_loc, y_loc)

	if(!isnum(x_loc) || !isnum(y_loc))
		return null

	if(!field_check(x_loc, y_loc))
		return null

	var/key = "[x_loc],[y_loc]"
	return list(key, x_loc, y_loc)

#undef GAME_PLAYER_ONE
#undef GAME_PLAYER_TWO
#undef GAME_OVER
#undef GAME_OVER_DRAW
