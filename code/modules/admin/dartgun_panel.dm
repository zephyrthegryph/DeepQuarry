// Dartgun mixing control — structured TGUI.

/obj/item/gun/projectile/dartgun/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/item/gun/projectile/dartgun/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Dartgun", "[src] mixing control")
		ui.open()

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

/obj/item/gun/projectile/dartgun/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("toggle_mix")
			var/idx = text2num("[params["index"]]")
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
				Topic("stop_mix=[idx]", list("stop_mix" = "[idx]"))
			else
				Topic("mix=[idx]", list("mix" = "[idx]"))
			SStgui.update_uis(src)
			return TRUE
		if("eject_beaker")
			var/idx = text2num("[params["index"]]")
			Topic("eject=[idx]", list("eject" = "[idx]"))
			SStgui.update_uis(src)
			return TRUE
		if("eject_cart")
			Topic("eject_cart=1", list("eject_cart" = "1"))
			SStgui.update_uis(src)
			return TRUE
