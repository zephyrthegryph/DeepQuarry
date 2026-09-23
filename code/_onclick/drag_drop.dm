/*
	MouseDrop:

	Called on the atom you're dragging.  In a lot of circumstances we want to use the
	recieving object instead, so that's the default action.  This allows you to drag
	almost anything into a trash can.
*/

/atom/proc/CanMouseDrop(atom/over, mob/user = usr)
	if(!user || !over)
		return FALSE
	if(user.incapacitated())
		return FALSE
	if(!src.Adjacent(user) || !over.Adjacent(user))
		return FALSE // should stop you from dragging through windows
	return TRUE

// /atom/MouseDrop routes through the input router as the Drag action (router.dm).

/atom/proc/MouseDrop_T(atom/dropping, mob/user, src_location, over_location, src_control, over_control, params)
	return
