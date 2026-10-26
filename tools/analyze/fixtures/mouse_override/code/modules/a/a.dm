/obj/thing/Click(location, control, params)
	return ..()

/obj/thing/proc/MouseDrop(atom/over)
	return

/atom/movable/screen/button/MouseEntered()
	return

/atom/movable/screen/block_form
	Click()
		return
	MouseExited()
		return
	proc/MouseDown()
		return

/obj/thing/proc/fine()
	Click(null, null, "")
	src.MouseDrop(src)
	// /obj/commented/Click() is a comment
	var/s = "/obj/string/Click()"
	return

/obj/thing/proc/click_on_handler(datum/act/input/A)
	return TRUE

/obj/thing/Click_extra()
	return

/client/MouseWheel(delta_x, delta_y)
	return

/obj/thing/MouseDrop_T(atom/dropping, mob/user)
	return

/*
/obj/block_comment/Click()
	return
*/
