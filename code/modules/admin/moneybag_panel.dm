// Moneybag — structured TGUI.
//
// One row per coin type with a "Remove one" button. Uses the existing
// Topic handler since the coin-removal logic is fine where it is.

CAPABILITIES(/obj/item/moneybag)
	interface("Moneybag", title = "Moneybag", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	op("remove", ui_act("remove", arg("coin", schema_text(4096))), then(PROC_REF(ui_act_remove)))
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// /obj/item/moneybag's window data.
/obj/item/moneybag/ui_data(datum/act/eval/A)
	return list("counts" = count_coins())

/obj/item/moneybag/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!user)
		return FALSE
	user.set_machine(src)
	add_fingerprint(user)
	return TRUE

/obj/item/moneybag/proc/ui_act_remove(datum/act/op/A, coin)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/coin_type = "[coin]"
	moneybag_remove_coin(user, coin_type)
	SStgui.update_uis(src)
	return TRUE
