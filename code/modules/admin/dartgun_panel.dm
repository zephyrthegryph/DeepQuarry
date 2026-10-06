// Dartgun mixing control — structured TGUI.

CAPABILITIES(/obj/item/gun/projectile/dartgun)
	ref_many(nameof(mixing))
	interface("Dartgun", state = nameof(GLOB.tgui_default_state))
	op("toggle_mix", ui_act("toggle_mix", arg("index", num())), then(PROC_REF(ui_act_toggle_mix)))
	op("eject_beaker", ui_act("eject_beaker", arg("index", num())), then(PROC_REF(ui_act_eject_beaker)))
	op("eject_cart", ui_act("eject_cart"), then(PROC_REF(ui_act_eject_cart)))

/obj/item/gun/projectile/dartgun/ui_title(mob/user)
	return "[src] mixing control"

/// /obj/item/gun/projectile/dartgun's window data.
/obj/item/gun/projectile/dartgun/ui_data(datum/act/eval/A)
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

/obj/item/gun/projectile/dartgun/proc/ui_act_toggle_mix(datum/act/op/A, index)
	var/mob/user = A.actor
	var/idx = index
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
		dartgun_set_mixing(user, idx, FALSE)
	else
		dartgun_set_mixing(user, idx, TRUE)
	SStgui.update_uis(src)
	return TRUE

/obj/item/gun/projectile/dartgun/proc/ui_act_eject_beaker(datum/act/op/A, index)
	var/mob/user = A.actor
	var/idx = index
	dartgun_eject_beaker(user, idx)
	SStgui.update_uis(src)
	return TRUE

/obj/item/gun/projectile/dartgun/proc/ui_act_eject_cart(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	unload_ammo(user)
	SStgui.update_uis(src)
	return OP_OK
