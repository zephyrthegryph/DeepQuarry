// Moneybag — structured TGUI.
//
// One row per coin type with a "Remove one" button. Uses the existing
// Topic handler since the coin-removal logic is fine where it is.

/obj/item/moneybag/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/item/moneybag/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Moneybag", "Moneybag")
		ui.open()

/obj/item/moneybag/tgui_data(mob/user)
	return list("counts" = count_coins())

/obj/item/moneybag/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	var/mob/user = ui?.user
	if(!user)
		return
	user.set_machine(src)
	add_fingerprint(user)
	if(action == "remove")
		var/coin_type = "[params["coin"]]"
		Topic("remove=[coin_type]", list("remove" = coin_type))
		SStgui.update_uis(src)
		return TRUE
