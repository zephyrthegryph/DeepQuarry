
//////////////////////////
//Movable Screen Objects//
//   By RemieRichards	//
//////////////////////////


//Movable Screen Object
//Not tied to the grid, places it's center where the cursor is

/atom/movable/screen/movable
	mouse_drag_pointer = 'icons/effects/mouse_pointers/screen_drag.dmi'
	var/snap2grid = FALSE
	// TODO: Check if these can safely be deleted
	var/moved = FALSE
	var/locked = FALSE
	var/x_off = -16
	var/y_off = -16

//Snap Screen Object
//Tied to the grid, snaps to the nearest turf

/atom/movable/screen/movable/snap
	snap2grid = TRUE


/atom/movable/screen/movable/MouseDrop(over_object, src_location, over_location, src_control, over_control, params)
	if(locked) // no! i am locked! begone!
		return
	var/position = mouse_params_to_position(params, usr?.client?.view) // ALLOW(sys_usr_outside_verb): Click/MouseDrop run in the clicker's usr context
	if(!position)
		return

	screen_loc = position
	moved = screen_loc

/// Takes mouse parmas as input, returns a string representing the appropriate mouse position
/atom/movable/screen/movable/proc/mouse_params_to_position(params, view = null)
	var/list/modifiers = params2list(params)

	//No screen-loc information? abort.
	if(!LAZYACCESS(modifiers, SCREEN_LOC))
		return

	var/list/offset = screen_loc_to_offset(LAZYACCESS(modifiers, SCREEN_LOC), view)

	if(snap2grid) //Discard Pixel Values
		offset[1] = FLOOR(offset[1], ICON_SIZE_X) // drops any pixel offset
		offset[2] = FLOOR(offset[2], ICON_SIZE_Y) // drops any pixel offset
	else //Normalise Pixel Values (So the object drops at the center of the mouse, not 16 pixels off)
		offset[1] += x_off
		offset[2] += y_off
	return offset_to_screen_loc(offset[1], offset[2], view)

// Must stay for now, for subtypes
/atom/movable/screen/movable/proc/encode_screen_X(X)
	var/view_dist = world.view
	if(view_dist)
		view_dist = view_dist
	if(X > view_dist+1)
		. = "EAST-[view_dist *2 + 1-X]"
	else if(X < view_dist +1)
		. = "WEST+[X-1]"
	else
		. = "CENTER"

/atom/movable/screen/movable/proc/decode_screen_X(X)
	var/view_dist = world.view
	if(view_dist)
		view_dist = view_dist
	//Find EAST/WEST implementations
	if(findtext(X,"EAST-"))
		var/num = text2num(copytext(X,6)) //Trim EAST-
		if(!num)
			num = 0
		. = view_dist*2 + 1 - num
	else if(findtext(X,"WEST+"))
		var/num = text2num(copytext(X,6)) //Trim WEST+
		if(!num)
			num = 0
		. = num+1
	else if(findtext(X,"CENTER"))
		. = view_dist+1
	else
		. = text2num(X)

/atom/movable/screen/movable/proc/encode_screen_Y(Y)
	var/view_dist = world.view
	if(view_dist)
		view_dist = view_dist
	if(Y > view_dist+1)
		. = "NORTH-[view_dist*2 + 1-Y]"
	else if(Y < view_dist+1)
		. = "SOUTH+[Y-1]"
	else
		. = "CENTER"

/atom/movable/screen/movable/proc/decode_screen_Y(Y)
	var/view_dist = world.view
	if(view_dist)
		view_dist = view_dist
	if(findtext(Y,"NORTH-"))
		var/num = text2num(copytext(Y,7)) //Trim NORTH-
		if(!num)
			num = 0
		. = view_dist*2 + 1 - num
	else if(findtext(Y,"SOUTH+"))
		var/num = text2num(copytext(Y,7)) //Time SOUTH+
		if(!num)
			num = 0
		. = num+1
	else if(findtext(Y,"CENTER"))
		. = view_dist+1
	else
		. = text2num(Y)

//Debug procs
/client/proc/test_movable_UI()
	set category = VERB_CAT_DEBUG
	set name = "Spawn Movable UI Object"

	open_request(src, /datum/prompt/text, PROC_REF(movable_ui_position_answered), answerer = mob, question = "Where on the screen? (Formatted as 'X,Y' e.g: '1,1' for bottom left)", title = "Spawn Movable UI Object", max_len = MAX_MESSAGE_LEN, encode = TRUE, timeout = 0)

/client/proc/movable_ui_position_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/screen_l = A.answer.answer_value
	if(!screen_l)
		return

	var/atom/movable/screen/movable/M = new()
	M.name = "Movable UI Object"
	M.icon_state = "block"
	M.maptext = "Movable"
	M.maptext_width = 64

	M.screen_loc = screen_l

	screen += M


/client/proc/test_snap_UI()
	set category = VERB_CAT_DEBUG
	set name = "Spawn Snap UI Object"

	open_request(src, /datum/prompt/text, PROC_REF(snap_ui_position_answered), answerer = mob, question = "Where on the screen? (Formatted as 'X,Y' e.g: '1,1' for bottom left)", title = "Spawn Snap UI Object", max_len = MAX_MESSAGE_LEN, encode = TRUE, timeout = 0)

/client/proc/snap_ui_position_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/screen_l = A.answer.answer_value
	if(!screen_l)
		return

	var/atom/movable/screen/movable/snap/S = new()
	S.name = "Snap UI Object"
	S.icon_state = "block"
	S.maptext = "Snap"
	S.maptext_width = 64

	S.screen_loc = screen_l

	screen += S
