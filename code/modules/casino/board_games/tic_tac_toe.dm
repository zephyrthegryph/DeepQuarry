#define GAME_PLAYER_ONE 1
#define GRID_SIZE 3

/obj/structure/casino_table/board_game/tic_tac_toe
	name = GAME_TIC_TAC_TOE
	desc = "A small tic-tac-toe board."
	icon_state = "gamble_toe"
	game_ui = /datum/board_game/four_row/tic_tac_toe

/datum/board_game/four_row/tic_tac_toe
	name = GAME_TIC_TAC_TOE
	table_icon = "gamble_toe"
	grid_x_size = GRID_SIZE
	grid_y_size = GRID_SIZE
	win_count = GRID_SIZE

/datum/board_game/four_row/tic_tac_toe/tgui_static_data(mob/user)
	return list(
		"colors" = possible_colors - "blue"
	)

/datum/board_game/four_row/tic_tac_toe/game_place_chip(mob/user, list/params, extra)
	var/list/validated_data = validate_coords(params["loc_x"], params["loc_y"])
	if(!validated_data)
		return FALSE

	var/key = validated_data[1]
	if(LAZYACCESS(placed_chips_pone, key) || LAZYACCESS(placed_chips_ptwo, key))
		return FALSE

	var/x_loc = validated_data[2]
	var/y_loc = validated_data[3]

	if(game_state == GAME_PLAYER_ONE)
		LAZYSET(placed_chips_pone, key, TRUE)
	else
		LAZYSET(placed_chips_ptwo, key, TRUE)

	validate_victory(x_loc, y_loc, user.name)
	return TRUE

/datum/board_game/four_row/tic_tac_toe/set_new_size(new_size)
	return FALSE

/datum/board_game/four_row/change_win_count(new_count)
	return FALSE

#undef GAME_PLAYER_ONE
#undef GRID_SIZE

/// /datum/board_game/four_row/tic_tac_toe's "game" sub-actions (a nested message its window op routes): each one's arguments go through their schemas first.
/datum/board_game/four_row/tic_tac_toe/game_subaction(action, list/data, mob/user, extra)
	switch(action)
		if("place_chip")
			var/list/typed = payload_args(src, data, list("loc_x" = num(), "loc_y" = num()))
			return typed ? game_place_chip(user, typed, extra) : FALSE
	return ..()
