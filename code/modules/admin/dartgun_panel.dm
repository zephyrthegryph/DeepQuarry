// Dartgun mixing control — structured TGUI.

/obj/item/gun/projectile/dartgun/tgui_state(mob/user)
	return GLOB.tgui_default_state

DECLARE_UI(/obj/item/gun/projectile/dartgun, "Dartgun")

/obj/item/gun/projectile/dartgun/ui_title(mob/user)
	return "[src] mixing control"

/obj/item/gun/projectile/dartgun/tgui_data(mob/user)
	var/list/data = list()
	var/list/beaker_rows = list()
	var/i = 0
	for(var/obj/item/reagent_containers/glass/beaker/B in beakers)
		i++
		var/list/reagents = list()
		if(B.reagents && B.reagents.reagent_list.len)
			for(var/datum/reagent/R in B.reagents.reagent_list)
				reagents += list(list("name" = R.name, "volume" = R.volume))
		beaker_rows += list(list(
			"index" = i,
			"reagents" = reagents,
			"mixing" = !!check_beaker_mixing(B),
		))
	data["beakers"] = beaker_rows
	if(ammo_magazine)
		data["ammo_count"] = ammo_magazine.stored_ammo ? ammo_magazine.stored_ammo.len : 0
	else
		data["ammo_count"] = null
	return data

UI_ACT(/obj/item/gun/projectile/dartgun, "toggle_mix", ui_act_toggle_mix, UI_ARG_NUM("index"))
UI_ACT_PROC(/obj/item/gun/projectile/dartgun, ui_act_toggle_mix)
	var/idx = params["index"]
	if(!isnum(idx))
		return
	// Mirror the legacy logic: pick mix or stop_mix based on current state.
	var/obj/item/reagent_containers/glass/beaker/B
	var/i = 0
	for(B in beakers)
		i++
		if(i == idx)
			break
	if(!B)
		return TRUE
	if(check_beaker_mixing(B))
		dartgun_set_mixing(ui.user, idx, FALSE)
	else
		dartgun_set_mixing(ui.user, idx, TRUE)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/item/gun/projectile/dartgun, "eject_beaker", ui_act_eject_beaker, UI_ARG_NUM("index"))
UI_ACT_PROC(/obj/item/gun/projectile/dartgun, ui_act_eject_beaker)
	var/idx = params["index"]
	dartgun_eject_beaker(ui.user, idx)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/item/gun/projectile/dartgun, "eject_cart", ui_act_eject_cart)
UI_ACT_PROC(/obj/item/gun/projectile/dartgun, ui_act_eject_cart)
	add_fingerprint(ui.user)
	unload_ammo(ui.user)
	SStgui.update_uis(src)
	return TRUE
