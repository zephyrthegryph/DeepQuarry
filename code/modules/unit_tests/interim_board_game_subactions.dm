/// A board game's moves come inside "game_action" (a sub-action and its data): the game routes them itself, its arguments go through their schemas,
/// and only the player whose turn it is moves.
/datum/unit_test/interim_board_game_subactions/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/one = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/two = allocate(/mob/living/carbon/human, T)
	var/obj/structure/casino_table/board_game/checkers/table = allocate(/obj/structure/casino_table/board_game/checkers, T)
	var/datum/board_game/checkers/game = table.game_ui
	TEST_ASSERT(istype(game), "the checkers table holds a checkers game")
	TEST_ASSERT(test_op_committed(op_ui_act(one, game, "be_player_one")), "the first player takes white")
	TEST_ASSERT(test_op_committed(op_ui_act(two, game, "be_player_two")), "the second player takes black")
	TEST_ASSERT(test_op_committed(op_ui_act(one, game, "start_game")), "the game starts")
	var/piece_x
	var/piece_y
	for(var/y in 1 to length(game.current_board))
		var/list/row = game.current_board[y]
		for(var/x in 1 to length(row))
			var/piece = row[x]
			if(piece && piece[1] == "w")
				piece_x = x
				piece_y = y
	TEST_ASSERT(piece_x, "the board has a white piece")
	op_ui_act(two, game, "game_action", list("action" = "select_figure", "data" = list("loc_x" = piece_x, "loc_y" = piece_y)))
	TEST_ASSERT(!LAZYLEN(game.selected_figure), "black cannot select on white's turn")
	op_ui_act(one, game, "game_action", list("action" = "select_figure", "data" = list("loc_x" = "nowhere", "loc_y" = piece_y)))
	TEST_ASSERT(!LAZYLEN(game.selected_figure), "a coordinate that is not a number refuses the move")
	op_ui_act(one, game, "game_action", list("action" = "select_figure", "data" = list("loc_x" = "[piece_x]", "loc_y" = piece_y)))
	TEST_ASSERT_EQUAL(LAZYACCESS(game.selected_figure, 1), piece_x, "a numeric text coordinate is read as a number, as the old row did")
	TEST_ASSERT_EQUAL(LAZYACCESS(game.selected_figure, 2), piece_y, "white selects its own piece")
