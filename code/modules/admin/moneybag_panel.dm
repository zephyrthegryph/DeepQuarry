// Moneybag — structured TGUI.
//
// One row per coin type with a "Remove one" button. Uses the existing
// Topic handler since the coin-removal logic is fine where it is.

/obj/item/moneybag/tgui_state(mob/user)
	return GLOB.tgui_default_state

DECLARE_UI(/obj/item/moneybag, "Moneybag", UI_TITLE("Moneybag"))

/obj/item/moneybag/tgui_data(mob/user)
	return list("counts" = count_coins())

/obj/item/moneybag/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!user)
		return FALSE
	user.set_machine(src)
	add_fingerprint(user)
	return TRUE

UI_ACT(/obj/item/moneybag, "remove", ui_act_remove, UI_ARG_TEXT("coin"))
UI_ACT_PROC(/obj/item/moneybag, ui_act_remove)
	var/coin_type = "[params["coin"]]"
	moneybag_remove_coin(user, coin_type)
	SStgui.update_uis(src)
	return TRUE
