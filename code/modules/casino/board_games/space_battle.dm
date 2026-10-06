#define GAME_PLACE_SHIPS 1
#define GAME_PLAYER_ONE 2
#define GAME_PLAYER_TWO 3
#define GAME_OVER 4
#define GRID_SIZE 10
#define PLAYER_ONE_PLACED_SHIPS 0x1
#define PLAYER_TWO_PLACED_SHIPS 0x2

/obj/structure/casino_table/board_game/space_battle
	name = GAME_SPACE_BATTLE
	desc = "A game with the goal to destroy the opponent's ships."
	icon_state = "gamble_space"
	game_ui = /datum/board_game/space_battle

/datum/board_game/space_battle
	name = GAME_SPACE_BATTLE
	table_icon = "gamble_space"
	var/mob/player_one
	var/mob/player_two
	var/list/ship_count_pone
	var/list/ship_count_ptwo
	var/list/shots_fired_pone = list() // ALLOW(instance_list): d: board state written through an alias (current_shots[key] = hit); one per game table
	var/list/shots_fired_ptwo = list() // ALLOW(instance_list): d: board state written through an alias (current_shots[key] = hit); one per game table
	var/list/ships_placed_pone = list() // ALLOW(instance_list): d: board state written through an alias; one per game table
	var/list/ships_placed_ptwo = list() // ALLOW(instance_list): d: board state written through an alias; one per game table
	var/list/destroyed_ships_pone
	var/list/destroyed_ships_ptwo
	var/static/list/total_ships = list(
		"Carrier" = 1,
		"Cruiser" = 2,
		"Corvette" = 3,
		"Figher" = 4,
	)
	var/static/list/ship_sizes = list(
		"Carrier" = 6,
		"Cruiser" = 4,
		"Corvette" = 3,
		"Figher" = 2,
	)
	var/winner
	var/ships_have_been_placed = NONE

CAPABILITIES(/datum/board_game/space_battle)
	interface("SpaceBattle", state = nameof(GLOB.tgui_board_game_state))
	op("be_player_one", ui_act("be_player_one"), then(PROC_REF(ui_act_be_player_one)))
	op("be_player_two", ui_act("be_player_two"), then(PROC_REF(ui_act_be_player_two)))
	op("swap_players", ui_act("swap_players"), then(PROC_REF(ui_act_swap_players)))
	op("clear_game", ui_act("clear_game"), then(PROC_REF(ui_act_clear_game)))
	op("prepare_game", ui_act("prepare_game"), then(PROC_REF(ui_act_prepare_game)))
	op("start_game", ui_act("start_game"), then(PROC_REF(ui_act_start_game)))
	op("play_again", ui_act("play_again"), then(PROC_REF(ui_act_play_again)))
	op("play_again_swapped", ui_act("play_again_swapped"), then(PROC_REF(ui_act_play_again_swapped)))
	op("place_ship", ui_act("place_ship", arg("ship")), then(PROC_REF(ui_act_place_ship)))
	op("remove_ship", ui_act("remove_ship", arg("loc_x", num()), arg("loc_y", num()), arg("player", num())), then(PROC_REF(ui_act_remove_ship)))
	op("game_action", ui_act("game_action", arg("action", schema_text(4096)), arg("data")), then(PROC_REF(ui_act_game_action)))

/datum/board_game/space_battle/tgui_static_data(mob/user)
	return list(
		"ship_sizes" = ship_sizes,
		"total_ships" = total_ships
	)

/// /datum/board_game/space_battle's window data.
/datum/board_game/space_battle/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/mob/player_one_mob = player_one
	var/mob/player_two_mob = player_two

	var/list/visible_ships = list()
	if(user == player_one_mob || game_state == GAME_OVER)
		visible_ships += ships_placed_pone
	if(user == player_two_mob || game_state == GAME_OVER)
		visible_ships += ships_placed_ptwo

	return list(
		"current_player" = user,
		"player_one" = player_one_mob,
		"player_two" = player_two_mob,
		"all_placed" = ships_have_been_placed,
		"shots_fired_pone" = shots_fired_pone,
		"shots_fired_ptwo" = shots_fired_ptwo,
		"destroyed_ships_pone" = (destroyed_ships_pone || list()),
		"destroyed_ships_ptwo" = (destroyed_ships_ptwo || list()),
		"visible_ships" = visible_ships,
		"ship_count_pone" = (ship_count_pone || list()),
		"ship_count_ptwo" = (ship_count_ptwo || list()),
		"game_state" = game_state,
		"winner" = winner,
		"has_won" = winner == user.name
	)

/datum/board_game/space_battle/proc/ui_act_be_player_one(datum/act/op/A)
	var/mob/user = A.actor
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_one == user)
		rel_clear(src, nameof(player_one))
		return TRUE
	rel_set(src, nameof(player_one), user)
	return TRUE

/datum/board_game/space_battle/proc/ui_act_be_player_two(datum/act/op/A)
	var/mob/user = A.actor
	if(game_state != GAME_SETUP)
		return FALSE
	if(player_two == user)
		rel_clear(src, nameof(player_two))
		return TRUE
	rel_set(src, nameof(player_two), user)
	return TRUE

/datum/board_game/space_battle/proc/ui_act_swap_players(datum/act/op/A)
	if(game_state != GAME_SETUP)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	var/mob/temp_player = player_one
	rel_set(src, nameof(player_one), player_two)
	rel_set(src, nameof(player_two), temp_player)

/datum/board_game/space_battle/proc/ui_act_clear_game(datum/act/op/A)
	if(game_state == GAME_SETUP)
		return FALSE
	reset(TRUE)
	return TRUE

/datum/board_game/space_battle/proc/ui_act_prepare_game(datum/act/op/A)
	if(game_state != GAME_SETUP)
		return FALSE
	var/mob/player_one_mob = player_one
	var/mob/player_two_mob = player_two
	if(!player_one_mob || !player_two_mob)
		return FALSE
	game_state = GAME_PLACE_SHIPS
	ship_count_pone = get_remaining_ships(1)
	ship_count_ptwo = get_remaining_ships(2)
	return TRUE

/datum/board_game/space_battle/proc/ui_act_start_game(datum/act/op/A)
	if(game_state != GAME_PLACE_SHIPS)
		return FALSE
	if(!(ships_have_been_placed == (PLAYER_ONE_PLACED_SHIPS | PLAYER_TWO_PLACED_SHIPS)))
		return FALSE
	var/mob/player_one_mob = player_one
	var/mob/player_two_mob = player_two
	if(!player_one_mob || !player_two_mob)
		return FALSE
	ship_count_pone = get_alive_ships(1)
	ship_count_ptwo = get_alive_ships(2)
	game_state = GAME_PLAYER_ONE
	return TRUE

/datum/board_game/space_battle/proc/ui_act_play_again(datum/act/op/A)
	if(game_state < GAME_OVER)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	reset()
	return TRUE

/datum/board_game/space_battle/proc/ui_act_play_again_swapped(datum/act/op/A)
	if(game_state < GAME_OVER)
		return FALSE
	if(!player_one || !player_two)
		return FALSE
	reset()
	var/mob/temp_player = player_one
	rel_set(src, nameof(player_one), player_two)
	rel_set(src, nameof(player_two), temp_player)
	return TRUE

/datum/board_game/space_battle/proc/ui_act_place_ship(datum/act/op/A, ship)
	var/mob/user = A.actor
	if(!isnull(ship) && !islist(ship))
		return FALSE
	if(game_state != GAME_PLACE_SHIPS)
		return FALSE
	var/mob/player_one_mob = player_one
	var/mob/player_two_mob = player_two
	if(!player_one_mob || !player_two_mob)
		return FALSE

	var/list/ship_data = ship
	if(!ship_data["name"] || !ship_data["coords"])
		return FALSE

	var/player = ship_data["player"]
	if(!player)
		return FALSE

	if(player == 1 && user != player_one_mob)
		return FALSE
	if(player == 2 && user != player_two_mob)
		return FALSE

	var/allowed = total_ships[ship_data["name"]]
	if(!allowed)
		return FALSE

	var/list/current_ships
	if(player == 1)
		current_ships = ships_placed_pone
	else
		current_ships = ships_placed_ptwo

	var/count = 0
	for(var/list/existing in current_ships)
		if(existing["name"] == ship_data["name"])
			count++

	if(count >= allowed)
		return FALSE

	var/list/new_coords = ship_data["coords"]
	for(var/list/new_coord in new_coords)
		if(!isnum(new_coord[1]) || !isnum(new_coord[2]))
			return FALSE
		if(!field_check(new_coord[1], new_coord[2]))
			return FALSE

	for(var/list/existing_ship in current_ships)
		for(var/list/coord in existing_ship["coords"])
			for(var/list/new_coord in new_coords)
				if(coord[1] == new_coord[1] && coord[2] == new_coord[2])
					return FALSE

	UNTYPED_LIST_ADD(current_ships, ship_data)
	if(player == 1)
		ship_count_pone = get_remaining_ships(1)
	else
		ship_count_ptwo = get_remaining_ships(2)

	return TRUE

/datum/board_game/space_battle/proc/ui_act_remove_ship(datum/act/op/A, loc_x_arg, loc_y_arg, player_arg)
	var/mob/user = A.actor
	if(game_state != GAME_PLACE_SHIPS)
		return FALSE
	var/mob/player_one_mob = player_one
	var/mob/player_two_mob = player_two
	if(!player_one_mob || !player_two_mob)
		return FALSE

	var/player = player_arg
	if(player == 1 && user != player_one_mob)
		return FALSE
	if(player == 2 && user != player_two_mob)
		return FALSE

	var/list/ships
	if(player == 1)
		ships = ships_placed_pone
	else
		ships = ships_placed_ptwo

	var/loc_x = loc_x_arg
	var/loc_y = loc_y_arg
	for(var/i in length(ships) to 1 step -1)
		var/list/ship = ships[i]
		for(var/list/coord in ship["coords"])
			if(coord[1] == loc_x && coord[2] == loc_y)
				ships.Cut(i, i + 1)
				if(player == 1)
					ship_count_pone = get_remaining_ships(1)
				else
					ship_count_ptwo = get_remaining_ships(2)
				return TRUE
	return FALSE

/datum/board_game/space_battle/proc/ui_act_game_action(datum/act/op/A, action_arg, data)
	var/mob/user = A.actor
	if(!isnull(data) && !islist(data))
		return FALSE
	if(user == player_one && game_state == GAME_PLAYER_ONE)
		if(data["player"] == 1)
			return FALSE
		if(game_subaction(action_arg, data, user))
			if(game_state < GAME_OVER)
				game_state = GAME_PLAYER_TWO
			return TRUE
	if(user == player_two && game_state == GAME_PLAYER_TWO)
		if(data["player"] == 2)
			return FALSE
		if(game_subaction(action_arg, data, user))
			if(game_state < GAME_OVER)
				game_state = GAME_PLAYER_ONE
			return TRUE
	return FALSE

/datum/board_game/space_battle/proc/reset(full)
	LAZYCLEARLIST(ship_count_pone)
	LAZYCLEARLIST(ship_count_ptwo)
	shots_fired_pone.Cut()
	shots_fired_ptwo.Cut()
	ships_placed_pone.Cut()
	ships_placed_ptwo.Cut()
	LAZYCLEARLIST(destroyed_ships_pone)
	LAZYCLEARLIST(destroyed_ships_ptwo)
	winner = null
	ships_have_been_placed = NONE
	if(full)
		game_state = GAME_SETUP
		rel_clear(src, nameof(player_one))
		rel_clear(src, nameof(player_two))
	else
		game_state = GAME_PLACE_SHIPS

/datum/board_game/space_battle/proc/game_fire_shot(mob/user, list/params, extra)
	var/list/validated_data = validate_coords(params["loc_x"], params["loc_y"])
	if(!validated_data)
		return FALSE

	var/key = validated_data[1]

	var/list/opponent_ships
	var/list/current_shots

	if(game_state == GAME_PLAYER_ONE)
		current_shots = shots_fired_pone
		opponent_ships = ships_placed_ptwo
	else
		current_shots = shots_fired_ptwo
		opponent_ships = ships_placed_pone

	if(!isnull(current_shots[key]))
		return FALSE

	var/hit = 0
	for(var/list/ship in opponent_ships)
		for(var/coord in ship["coords"])
			if(coord[1] == validated_data[2] && coord[2] == validated_data[3])
				hit = 1
				break
		if(hit)
			break

	current_shots[key] = hit

	if(hit)
		validate_victory(opponent_ships, current_shots, user)

	return TRUE

/datum/board_game/space_battle/proc/validate_victory(list/opponent_ships, list/current_shots, mob/user)
	for(var/list/ship in opponent_ships)
		var/ship_destroyed = TRUE
		for(var/coord in ship["coords"])
			var/key = "[coord[1]],[coord[2]]"
			if(!current_shots[key])
				ship_destroyed = FALSE
				break

		if(ship_destroyed)
			if(game_state == GAME_PLAYER_ONE)
				if(!(LAZYFIND(destroyed_ships_pone, ship)))
					UNTYPED_LIST_ADD(destroyed_ships_pone, ship)
					ship_count_pone = get_alive_ships(1)
			else
				if(!(LAZYFIND(destroyed_ships_ptwo, ship)))
					UNTYPED_LIST_ADD(destroyed_ships_ptwo, ship)
					ship_count_ptwo = get_alive_ships(2)

	for(var/list/ship in opponent_ships)
		var/key
		for(var/coord in ship["coords"])
			key = "[coord[1]],[coord[2]]"
			if(!current_shots[key])
				return

	winner = user.name
	game_state = GAME_OVER

/datum/board_game/space_battle/proc/field_check(new_x_location, new_y_location)
	if(new_x_location < 1 || new_x_location > GRID_SIZE)
		return FALSE
	if(new_y_location < 1 || new_y_location > GRID_SIZE)
		return FALSE
	return TRUE

/datum/board_game/space_battle/proc/validate_coords(x_loc, y_loc)

	if(!isnum(x_loc) || !isnum(y_loc))
		return null

	if(!field_check(x_loc, y_loc))
		return null

	var/key = "[x_loc],[y_loc]"
	return list(key, x_loc, y_loc)

/datum/board_game/space_battle/proc/get_remaining_ships(player)
	var/list/remaining_ships = list()
	var/list/placed_ships
	var/ship_placed_flag

	if(player == 1)
		placed_ships = ships_placed_pone
		ship_placed_flag = PLAYER_ONE_PLACED_SHIPS
	else if(player == 2)
		placed_ships = ships_placed_ptwo
		ship_placed_flag = PLAYER_TWO_PLACED_SHIPS
	else
		return remaining_ships

	for(var/ship_name in ship_sizes)
		var/allowed_count = total_ships[ship_name]
		var/placed_count = 0

		for(var/list/placed_ship in placed_ships)
			if(placed_ship["name"] == ship_name)
				placed_count++

		var/remaining_count = allowed_count - placed_count
		if(remaining_count > 0)
			remaining_ships[ship_name] = remaining_count

	if(length(remaining_ships))
		ships_have_been_placed &= ~ship_placed_flag
	else
		ships_have_been_placed |= ship_placed_flag

	return remaining_ships

/datum/board_game/space_battle/proc/get_alive_ships(player)
	var/list/alive_ships = list()
	var/list/ships

	if(player == 1)
		ships = ships_placed_pone
	else if(player == 2)
		ships = ships_placed_ptwo
	else
		return alive_ships

	for(var/list/ship in ships)
		if(game_state == GAME_PLAYER_ONE && !(LAZYFIND(destroyed_ships_pone, ship)))
			alive_ships[ship["name"]] = length(alive_ships) ? alive_ships[ship["name"]] + 1 : 1

		if(game_state == GAME_PLAYER_TWO && !(LAZYFIND(destroyed_ships_ptwo, ship)))
			alive_ships[ship["name"]] = length(alive_ships) ? alive_ships[ship["name"]] + 1 : 1

	return alive_ships

#undef GAME_PLACE_SHIPS
#undef GAME_PLAYER_ONE
#undef GAME_PLAYER_TWO
#undef GAME_OVER
#undef GRID_SIZE
#undef PLAYER_ONE_PLACED_SHIPS
#undef PLAYER_TWO_PLACED_SHIPS

/// /datum/board_game/space_battle's "game" sub-actions (a nested message its window op routes): each one's arguments go through their schemas first.
/datum/board_game/space_battle/game_subaction(action, list/data, mob/user, extra)
	switch(action)
		if("fire_shot")
			var/list/typed = payload_args(src, data, list("loc_x" = num(), "loc_y" = num()))
			return typed ? game_fire_shot(user, typed, extra) : FALSE
	return ..()
