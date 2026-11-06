/obj/test/tgui_interact(mob/user)
	var/a = text2num(params["n"])
	ui = new(user, src, "T")

/obj/test/tgui_data(mob/user)
	return list()
