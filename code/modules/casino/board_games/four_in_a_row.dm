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

CAPABILITIES(/datum/board_game/four_row)
	interface("FourInARow", state = nameof(GLOB.tgui_board_game_state))
	op("be_player_one", ui_act("be_player_one"), then(PROC_REF(ui_act_be_player_one)))
	op("be_player_two", ui_act("be_player_two"), then(PROC_REF(ui_act_be_player_two)))
	op("swap_players", ui_act("swap_players"), then(PROC_REF(ui_act_swap_players)))
	op("set_color_one", ui_act("set_color_one", arg("color")), then(PROC_REF(ui_act_set_color_one)))
	op("set_color_two", ui_act("set_color_two", arg("color")), then(PROC_REF(ui_act_set_color_two)))
	op("change_size", ui_act("change_size", arg("size", num())), then(PROC_REF(ui_act_change_size)))
	op("change_win", ui_act("change_win", arg("count", num())), then(PROC_REF(ui_act_change_win)))
	op("clear_game", ui_act("clear_game"), then(PROC_REF(ui_act_clear_game)))
	op("start_game", ui_act("start_game"), then(PROC_REF(ui_act_start_game)))
	op("play_again", ui_act("play_again"), then(PROC_REF(ui_act_play_again)))
	op("play_again_swapped", ui_act("play_again_swapped"), then(PROC_REF(ui_act_play_again_swapped)))
	op("game_action", ui_act("game_action", arg("action", schema_text(64)), arg("data")), then(PROC_REF(ui_act_game_action)))

/datum/board_game/four_row/tgui_static_data(mob/user)
	return list(
		"colors" = possible_colors
	)

/// /datum/board_game/four_row's window data.
/datum/board_game/four_row/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
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
		"has_won" = winner == user.name,
		"winning_tiles" = (winning_tiles || list()),
	)

/datum/board_game/four_row/proc/ui_act_be_player_one(datum/act/op/A)
	var/mob/user = A.actor
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_one == user)
		rel_clear(src, nameof(player_one))
		return TRUE
	rel_set(src, nameof(player_one), user)
	return TRUE

/datum/board_game/four_row/proc/ui_act_be_player_two(datum/act/op/A)
	var/mob/user = A.actor
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_two == user)
		rel_clear(src, nameof(player_two))
		return TRUE
	rel_set(src, nameof(player_two), user)
	return TRUE

/datum/board_game/four_row/proc/ui_act_swap_players(datum/act/op/A)
	if(game_state != GAME_SETUP)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	var/mob/temp_player = player_one
	rel_set(src, nameof(player_one), player_two)
	rel_set(src, nameof(player_two), temp_player)

/datum/board_game/four_row/proc/ui_act_set_color_one(datum/act/op/A, color)
	var/mob/user = A.actor
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_one != user)
		return FALSE
	var/new_color = color
	if(new_color == player_two_color)
		return FALSE
	if(!(new_color in possible_colors))
		return FALSE
	player_one_color = new_color
	return TRUE

/datum/board_game/four_row/proc/ui_act_set_color_two(datum/act/op/A, color)
	var/mob/user = A.actor
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_two != user)
		return FALSE
	var/new_color = color
	if(new_color == player_one_color)
		return FALSE
	if(!(new_color in possible_colors))
		return FALSE
	player_two_color = new_color
	return TRUE

/datum/board_game/four_row/proc/ui_act_change_size(datum/act/op/A, size)
	if(game_state != GAME_SETUP)
		return FALSE
	var/new_size = size
	return set_new_size(new_size)

/datum/board_game/four_row/proc/ui_act_change_win(datum/act/op/A, count)
	if(game_state != GAME_SETUP)
		return FALSE
	return change_win_count(count)

/datum/board_game/four_row/proc/ui_act_clear_game(datum/act/op/A)
	if(game_state == GAME_SETUP)
		return FALSE
	reset(TRUE)
	return TRUE

/datum/board_game/four_row/proc/ui_act_start_game(datum/act/op/A)
	if(game_state != GAME_SETUP)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	game_state = GAME_PLAYER_ONE
	return TRUE

/datum/board_game/four_row/proc/ui_act_play_again(datum/act/op/A)
	if(game_state < GAME_OVER)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	reset()
	return TRUE

/datum/board_game/four_row/proc/ui_act_play_again_swapped(datum/act/op/A)
	if(game_state < GAME_OVER)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	reset()
	var/mob/temp_player = player_one
	rel_set(src, nameof(player_one), player_two)
	rel_set(src, nameof(player_two), temp_player)
	return TRUE

/datum/board_game/four_row/proc/ui_act_game_action(datum/act/op/A, action_arg, data)
	var/mob/user = A.actor
	if(!isnull(data) && !islist(data))
		return FALSE
	if(user == player_one && game_state == GAME_PLAYER_ONE)
		if(game_subaction(action_arg, data, user))
			if(game_state < GAME_OVER)
				game_state = GAME_PLAYER_TWO
			return TRUE
	if(user == player_two && game_state == GAME_PLAYER_TWO)
		if(game_subaction(action_arg, data, user))
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
		rel_clear(src, nameof(player_one))
		rel_clear(src, nameof(player_two))
	else
		game_state = GAME_PLAYER_ONE

/datum/board_game/four_row/proc/game_place_chip(mob/user, list/params, extra)
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

/// /datum/board_game/four_row's "game" sub-actions (a nested message its window op routes): each one's arguments go through their schemas first.
/datum/board_game/four_row/game_subaction(action, list/data, mob/user, extra)
	switch(action)
		if("place_chip")
			var/list/typed = payload_args(src, data, list("loc_x" = num(), "loc_y" = num()))
			return typed ? game_place_chip(user, typed, extra) : FALSE
	return ..()
