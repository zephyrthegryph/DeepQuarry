/datum/tgui/proc/open_window(mob/user)
	ui = new(user, src, "Core")
	SStgui.try_update_ui(user, src)
	new /datum/tgui(user, src, "X")

/obj/exempt/tgui_interact(mob/user)
	return

/obj/exempt/tgui_data(mob/user)
	return list()

/obj/exempt/handler/proc/act_it(list/params)
	var/a = text2num(params["n"])
