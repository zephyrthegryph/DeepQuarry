/obj/item/airlock_electronics
	name = "airlock electronics"
	icon = 'icons/obj/doors/door_assembly.dmi'
	icon_state = "door_electronics"
	w_class = ITEMSIZE_SMALL //It should be tiny! -Agouri

	matter = list(MAT_STEEL = 50,MAT_GLASS = 50)

	req_one_access = list(ACCESS_ENGINE, ACCESS_TALON_ENGINEER) // Access to unlock the device, ignored if emagged
	var/list/apply_any_access = list(ACCESS_ENGINE) // Can apply any access, not just their own

	var/secure = 0 //if set, then wires will be randomized and bolts will drop if the door is broken
	var/list/conf_access = null
	var/one_access = 0 //if set to 1, door would receive req_one_access instead of req_access
	var/last_configurator = null
	var/locked = 1
	var/emagged = 0

/obj/item/airlock_electronics/emag_act(remaining_charges, mob/user)
	if(!emagged)
		emagged = 1
		to_chat(user, span_notice("You remove the access restrictions on [src]!"))
		return 1

/obj/item/airlock_electronics/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(!ishuman(user) && !istype(user, /mob/living/silicon/robot))
		return FALSE
	tgui_interact(user)

/obj/item/airlock_electronics/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AirlockElectronics", "Airlock Electronics")
		ui.open()

/obj/item/airlock_electronics/tgui_data(mob/user)
	var/list/data = list()
	data["locked"] = !!locked
	data["one_access"] = !!one_access
	data["last_configurator"] = last_configurator || ""
	data["all_selected"] = (conf_access == null)
	var/list/access_list = list()
	var/list/avail = get_available_accesses(user)
	for(var/acc in avail)
		access_list += list(list(
			"id" = acc,
			"name" = SSaccess.get_access_desc(acc),
			"selected" = conf_access && (acc in conf_access),
		))
	data["accesses"] = access_list
	return data

/obj/item/airlock_electronics/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	if(usr.stat || usr.restrained() || (!ishuman(usr) && !istype(usr, /mob/living/silicon)))
		return TRUE
	switch(action)
		if("login")
			if(emagged || issilicon(usr))
				locked = 0
				last_configurator = usr.name
			else if(isliving(usr))
				var/obj/item/card/id/id
				if(ishuman(usr))
					var/mob/living/carbon/human/H = usr
					id = H.get_idcard()
					if(id && check_access(id))
						locked = 0
						last_configurator = id.registered_name
				if(locked)
					var/obj/item/I = usr.get_active_hand()
					id = I?.GetID()
					if(id && check_access(id))
						locked = 0
						last_configurator = id.registered_name
			return TRUE
	if(locked)
		return TRUE
	switch(action)
		if("logout")
			locked = 1
			return TRUE
		if("one_access")
			one_access = !one_access
			return TRUE
		if("access")
			toggle_access(params["access"])
			return TRUE

/obj/item/airlock_electronics/proc/toggle_access(acc)
	if (acc == "all")
		conf_access = null
	else
		var/req = text2num(acc)

		if (conf_access == null)
			conf_access = list()

		if (!(req in conf_access))
			conf_access += req
		else
			conf_access -= req
			if (!conf_access.len)
				conf_access = null

/obj/item/airlock_electronics/proc/get_available_accesses(mob/user)
	var/obj/item/card/id/id
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		id = H.get_idcard()
	else if(issilicon(user))
		var/mob/living/silicon/R = user
		id = R.idcard

	// Nothing
	if(!id || !id.GetAccess())
		return list()

	// Has engineer access, can put any access
	else if(has_access(null, apply_any_access, id.GetAccess()))
		return SSaccess.get_all_station_access()

	// Not an engineer, can only pick your own accesses to program
	else
		return id.GetAccess()

/obj/item/airlock_electronics/secure
	name = "secure airlock electronics"
	desc = "designed to be somewhat more resistant to hacking than standard electronics."
	secure = 1

/obj/item/airlock_electronics/secure/emag_act(remaining_charges, mob/user)
	to_chat(user, span_warning("You don't appear to be able to bypass this hardened device!"))
	return -1
