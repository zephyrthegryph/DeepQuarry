// Moneybag — structured TGUI.
//
// One row per coin type with a "Remove one" button. Uses the existing
// Topic handler since the coin-removal logic is fine where it is.

DECLARE_UI_STATE(/obj/item/moneybag, GLOB.tgui_default_state)

DECLARE_UI(/obj/item/moneybag, "Moneybag", UI_TITLE("Moneybag"))

UI_DATA_REPLACE(/obj/item/moneybag, "merge:ui_data_obj_item_moneybag{counts:unknown}")

/// The computed part of /obj/item/moneybag's window data (declared on its UI_DATA row).
/obj/item/moneybag/proc/ui_data_obj_item_moneybag(mob/user, datum/tgui/ui, datum/tgui_state/state)
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
