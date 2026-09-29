#define GAME_PLAYING 1
#define GAME_LOST 2
#define GAME_WON 3
#define MAX_MINE_RATE 0.8

/obj/structure/casino_table/board_game/vore_sweeper
	name = GAME_SWEEPER
	desc = "A game about avoiding the mines"
	icon_state = "gamble_sweeper"
	game_ui = /datum/board_game/vore_sweeper

/datum/board_game/vore_sweeper
	name = GAME_SWEEPER
	table_icon = "gamble_sweeper"
	var/grid_size = 8
	var/mine_count = 10
	var/mob/dealer
	var/list/placed_mines
	var/list/revealed_fields
	var/list/placed_flags

/datum/board_game/vore_sweeper/New(atom/holder)
	. = ..()
	rel_set(src, nameof(parent), holder)

DECLARE_UI(/datum/board_game/vore_sweeper, "VoreSweeper")

UI_DATA_REPLACE(/datum/board_game/vore_sweeper, "merge:ui_data_datum_board_game_vore_sweeper{grid_size:num,mine_count:num,max_mines:num,dealer:unknown,placed_mines:bool,revealed_fields:bool,placed_flags:bool,game_state:unknown,is_dealer:bool}")

/// The computed part of /datum/board_game/vore_sweeper's window data (declared on its UI_DATA row).
/datum/board_game/vore_sweeper/proc/ui_data_datum_board_game_vore_sweeper(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/mob/dealer_mob = dealer

	var/placed_mine_data = game_state > GAME_PLAYING || (ui.user == dealer_mob) ? (placed_mines || list()) : null
	var/total_tiles = grid_size * grid_size
	return list(
		"grid_size" = grid_size,
		"mine_count" = mine_count,
		"max_mines" = round(total_tiles * MAX_MINE_RATE),
		"dealer" = dealer_mob,
		"placed_mines" = placed_mine_data,
		"revealed_fields" = (revealed_fields || list()),
		"placed_flags" = (placed_flags || list()),
		"game_state" = game_state,
		"is_dealer" = dealer_mob == ui.user
	)

UI_ACT(/datum/board_game/vore_sweeper, "be_dealer", ui_act_be_dealer)
UI_ACT_PROC(/datum/board_game/vore_sweeper, ui_act_be_dealer)
	if(game_state == GAME_PLAYING)
		return FALSE
	rel_set(src, nameof(/datum/board_game/vore_sweeper::dealer), ui.user)
	return TRUE

UI_ACT(/datum/board_game/vore_sweeper, "clear_dealer", ui_act_clear_dealer)
UI_ACT_PROC(/datum/board_game/vore_sweeper, ui_act_clear_dealer)
	var/mob/dealer_mob = dealer
	if(!dealer_mob)
		return FALSE
	if(dealer_mob == ui.user)
		parent().atom_say("[ui.user] stopped dealing.")
		rel_clear(src, nameof(/datum/board_game/vore_sweeper::dealer))
		return TRUE
	if(get_dist(ui.user, dealer_mob) > 3)
		parent().atom_say("Dealer has been cleared by [ui.user].")
		rel_clear(src, nameof(/datum/board_game/vore_sweeper::dealer))
		return TRUE
	return FALSE

UI_ACT(/datum/board_game/vore_sweeper, "restart_game", ui_act_restart_game)
UI_ACT_PROC(/datum/board_game/vore_sweeper, ui_act_restart_game)
	var/mob/dealer_mob = dealer
	if(game_state < GAME_PLAYING)
		return FALSE
	LAZYCLEARLIST(placed_mines)
	LAZYCLEARLIST(revealed_fields)
	LAZYCLEARLIST(placed_flags)
	if(!dealer_mob && game_state > GAME_PLAYING)
		auto_place_mines(ui.user, TRUE)
		return TRUE
	game_state = GAME_SETUP
	return TRUE

UI_ACT(/datum/board_game/vore_sweeper, "game_action", ui_act_game_action, UI_ARG_TEXT("action", 64), UI_ARG_LIST("data"))
UI_ACT_PROC(/datum/board_game/vore_sweeper, ui_act_game_action)
	if(can_play(ui.user) && ui_subdispatch(src, "game", params["action"], params["data"], ui.user, ui, state))
		return TRUE
	return FALSE

UI_ACT(/datum/board_game/vore_sweeper, "setup_action", ui_act_setup_action, UI_ARG_TEXT("action", 64), UI_ARG_LIST("data"))
UI_ACT_PROC(/datum/board_game/vore_sweeper, ui_act_setup_action)
	if(can_setup(ui.user) && ui_subdispatch(src, "setup", params["action"], params["data"], ui.user, ui, state))
		return TRUE
	return FALSE

/// Whether `user` may make a move now (players, not the dealer, during play).
/datum/board_game/vore_sweeper/proc/can_play(mob/user)
	if(user == dealer)
		return FALSE
	if(game_state != GAME_PLAYING)
		return FALSE
	return TRUE

UI_SUBACT(/datum/board_game/vore_sweeper, "game", "open_field", game_open_field, UI_ARG_NUM("loc_x"), UI_ARG_NUM("loc_y"))
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, game_open_field)
	var/list/validated_data = validate_coords(params["loc_x"], params["loc_y"])
	if(!validated_data)
		return FALSE
	var/key = validated_data[1]
	if(LAZYACCESS(placed_flags, key))
		return FALSE
	if(LAZYACCESS(revealed_fields, key))
		return FALSE
	if(LAZYACCESS(placed_mines, key))
		game_state = GAME_LOST
		LAZYSET(revealed_fields, key, "M")
		return TRUE
	var/mine_count = count_surrounding_mines(validated_data[2], validated_data[3])
	LAZYSET(revealed_fields, key, mine_count)
	if(!mine_count)
		reveal_empty_area(validated_data[2], validated_data[3])
	validate_victory()
	return TRUE

UI_SUBACT(/datum/board_game/vore_sweeper, "game", "toggle_flag", game_toggle_flag, UI_ARG_NUM("loc_x"), UI_ARG_NUM("loc_y"))
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, game_toggle_flag)
	var/list/validated_data = validate_coords(params["loc_x"], params["loc_y"])
	if(!validated_data)
		return FALSE
	var/key = validated_data[1]
	if(LAZYACCESS(revealed_fields, key))
		return FALSE
	if(LAZYACCESS(placed_flags, key))
		LAZYREMOVE(placed_flags, key)
		return TRUE
	LAZYSET(placed_flags, key, TRUE)
	validate_flag_victory()
	return TRUE

/datum/board_game/vore_sweeper/proc/validate_victory()
	var/total_tiles = grid_size * grid_size
	var/safe_tiles = total_tiles - length(placed_mines)
	if(length(revealed_fields) >= safe_tiles)
		game_state = GAME_WON

/datum/board_game/vore_sweeper/proc/validate_flag_victory()
	var/all_flagged = TRUE

	for(var/mine_key in placed_mines)
		if(LAZYACCESS(placed_mines, mine_key) && !LAZYACCESS(placed_flags, mine_key))
			all_flagged = FALSE
			break

	for(var/flag_key in placed_flags)
		if(!LAZYACCESS(placed_mines, flag_key))
			all_flagged = FALSE
			break

	if(!all_flagged)
		return

	for(var/x = 1 to grid_size)
		for(var/y = 1 to grid_size)
			var/key = "[x],[y]"

			if(LAZYACCESS(placed_mines, key))
				continue

			LAZYSET(revealed_fields, key, count_surrounding_mines(x, y))

	game_state = GAME_WON

/// Whether `user` may set the board up (the dealer, before play).
/datum/board_game/vore_sweeper/proc/can_setup(mob/user)
	if(user != dealer)
		return FALSE
	if(game_state != GAME_SETUP)
		return FALSE
	return TRUE

UI_SUBACT(/datum/board_game/vore_sweeper, "setup", "change_grid_size", setup_change_grid_size, UI_ARG_NUM("new_grid"))
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, setup_change_grid_size)
	var/new_grid_size = params["new_grid"]
	if(!new_grid_size)
		return FALSE
	if(new_grid_size < 4 || new_grid_size > 16)
		return FALSE
	validate_mine_count(mine_count, new_grid_size)
	grid_size = new_grid_size
	return TRUE

UI_SUBACT(/datum/board_game/vore_sweeper, "setup", "change_mine_count", setup_change_mine_count, UI_ARG_NUM("new_mines"))
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, setup_change_mine_count)
	var/new_mine_count = params["new_mines"]
	if(!new_mine_count)
		return FALSE
	validate_mine_count(new_mine_count, grid_size)
	return TRUE

UI_SUBACT(/datum/board_game/vore_sweeper, "setup", "place_mine", setup_place_mine, UI_ARG_NUM("loc_x"), UI_ARG_NUM("loc_y"))
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, setup_place_mine)
	if(length(placed_mines) >= mine_count)
		return FALSE
	var/list/validated_data = validate_coords(params["loc_x"], params["loc_y"])
	if(!validated_data)
		return FALSE
	var/key = validated_data[1]
	if(LAZYACCESS(placed_mines, key))
		return FALSE
	LAZYSET(placed_mines, key, TRUE)
	return TRUE

UI_SUBACT(/datum/board_game/vore_sweeper, "setup", "remove_mine", setup_remove_mine, UI_ARG_NUM("loc_x"), UI_ARG_NUM("loc_y"))
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, setup_remove_mine)
	if(game_state != GAME_SETUP)
		return FALSE
	if(length(placed_mines) <= 0)
		return FALSE
	var/list/validated_data = validate_coords(params["loc_x"], params["loc_y"])
	if(!validated_data)
		return FALSE
	var/key = validated_data[1]
	LAZYREMOVE(placed_mines, key)
	return TRUE

UI_SUBACT(/datum/board_game/vore_sweeper, "setup", "auto_place_mines", setup_auto_place_mines)
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, setup_auto_place_mines)
	return auto_place_mines(user)

UI_SUBACT(/datum/board_game/vore_sweeper, "setup", "auto_place_mines_self", setup_auto_place_mines_self)
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, setup_auto_place_mines_self)
	return auto_place_mines(user, TRUE)

UI_SUBACT(/datum/board_game/vore_sweeper, "setup", "clear_all_mines", setup_clear_all_mines)
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, setup_clear_all_mines)
	LAZYCLEARLIST(placed_mines)
	return TRUE

UI_SUBACT(/datum/board_game/vore_sweeper, "setup", "start_game", setup_start_game)
UI_SUBACT_PROC(/datum/board_game/vore_sweeper, setup_start_game)
	game_state = GAME_PLAYING
	return TRUE

/datum/board_game/vore_sweeper/proc/reveal_empty_area(x, y)
	var/list/to_check = list(list(x, y))
	var/list/checked = list()
	var/i = 1

	while(i <= length(to_check))
		var/current = to_check[i]
		i += 1
		var/cx = current[1]
		var/cy = current[2]
		var/key = "[cx],[cy]"

		if(checked[key])
			continue
		checked[key] = TRUE

		if(LAZYACCESS(revealed_fields, key) || LAZYACCESS(placed_flags, key))
			continue

		var/adjacent_mines = count_surrounding_mines(cx, cy)
		LAZYSET(revealed_fields, key, adjacent_mines)

		if(adjacent_mines == 0)
			for(var/dx = -1 to 1)
				for(var/dy = -1 to 1)
					if(dx == 0 && dy == 0)
						continue
					var/nx = cx + dx
					var/ny = cy + dy
					if(field_check(nx, ny))
						to_check += list(list(nx, ny))

/datum/board_game/vore_sweeper/proc/auto_place_mines(mob/user, play)
	var/placed = length(placed_mines)
	if(placed && play)
		to_chat(user, span_warning("You can't do this while there are mines placed."))
	while(placed < mine_count)
		var/x = rand(1, grid_size)
		var/y = rand(1, grid_size)
		var/key = "[x],[y]"
		if(!LAZYACCESS(placed_mines, key))
			LAZYSET(placed_mines, key, TRUE)
			placed++
	if(play)
		rel_clear(src, nameof(dealer))
		game_state = GAME_PLAYING
	return TRUE

/datum/board_game/vore_sweeper/proc/field_check(new_x_location, new_y_location)
	if(new_x_location < 1 || new_x_location > grid_size)
		return FALSE
	if(new_y_location < 1 || new_y_location > grid_size)
		return FALSE
	return TRUE

/datum/board_game/vore_sweeper/proc/count_surrounding_mines(x, y)
	var/count = 0

	for(var/dx = -1 to 1)
		for(var/dy = -1 to 1)
			if(dx == 0 && dy == 0)
				continue

			var/check_x = x + dx
			var/check_y = y + dy

			if(LAZYACCESS(placed_mines, "[check_x],[check_y]"))
				count++

	return count

/datum/board_game/vore_sweeper/proc/validate_mine_count(mines, size)
	var/total_tiles = size * size
	var/max_mines = round(total_tiles * MAX_MINE_RATE)
	// Reject non-numeric/sub-1 counts: a negative or zero count would otherwise slip
	// past the upper bound and break grid generation.
	if(!isnum(mines) || mines < 1)
		parent().atom_say("The grid must have at least one mine.")
		mine_count = 1
		return
	if(mines <= max_mines)
		mine_count = round(mines)
		return
	parent().atom_say("The grid with [total_tiles] tiles only supports a maximum of [max_mines] mines.")
	mine_count = max_mines

/datum/board_game/vore_sweeper/proc/validate_coords(x_loc, y_loc)

	if(!isnum(x_loc) || !isnum(y_loc))
		return null

	if(!field_check(x_loc, y_loc))
		return null

	var/key = "[x_loc],[y_loc]"
	return list(key, x_loc, y_loc)

#undef GAME_PLAYING
#undef GAME_LOST
#undef GAME_WON
#undef MAX_MINE_RATE
