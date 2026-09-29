MATERIAL_MIX(/obj/item/airlock_electronics, list(MAT_STEEL = 50,MAT_GLASS = 50))
/obj/item/airlock_electronics
	name = "airlock electronics"
	icon = 'icons/obj/doors/door_assembly.dmi'
	icon_state = "door_electronics"
	w_class = ITEMSIZE_SMALL //It should be tiny! -Agouri


	req_one_access = list(ACCESS_ENGINE, ACCESS_TALON_ENGINEER) // Access to unlock the device, ignored if emagged // Add talon
	var/static/list/apply_any_access = list(ACCESS_ENGINE) // Can apply any access, not just their own

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

// TGUI migration. attack_self opens AirlockElectronics.tsx;
// the Topic dispatch moves to tgui_act.
DECLARE_INTERACTIONS(/obj/item/airlock_electronics, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/airlock_electronics/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!ishuman(user) && !istype(user, /mob/living/silicon/robot))
		return TRUE
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/item/airlock_electronics, "AirlockElectronics", UI_TITLE("Airlock Electronics"))

UI_DATA_REPLACE(/obj/item/airlock_electronics, "merge:ui_data_obj_item_airlock_electronics{locked:bool,one_access:bool,last_configurator:bool,all_selected:bool,accesses:list}")

/// The computed part of /obj/item/airlock_electronics's window data (declared on its UI_DATA row).
/obj/item/airlock_electronics/proc/ui_data_obj_item_airlock_electronics(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/obj/item/airlock_electronics/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(usr.stat || usr.restrained() || (!ishuman(usr) && !istype(usr, /mob/living/silicon)))
		return FALSE
	return TRUE

UI_ACT(/obj/item/airlock_electronics, "login", ui_act_login)
UI_ACT_PROC(/obj/item/airlock_electronics, ui_act_login)
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

UI_ACT(/obj/item/airlock_electronics, "logout", ui_act_logout)
UI_ACT_PROC(/obj/item/airlock_electronics, ui_act_logout)
	if(locked)
		return TRUE
	locked = 1
	return TRUE

UI_ACT(/obj/item/airlock_electronics, "one_access", ui_act_one_access)
UI_ACT_PROC(/obj/item/airlock_electronics, ui_act_one_access)
	if(locked)
		return TRUE
	one_access = !one_access
	return TRUE

UI_ACT(/obj/item/airlock_electronics, "access_all", ui_act_access_all)
UI_ACT_PROC(/obj/item/airlock_electronics, ui_act_access_all)
	if(locked)
		return TRUE
	// Clears all access requirements; only allow users who may program any access.
	var/list/available = get_available_accesses(usr)
	if(length(available) && length(available) >= length(SSaccess.get_all_station_access()))
		conf_access = null
	return TRUE

UI_ACT(/obj/item/airlock_electronics, "access", ui_act_access, UI_ARG_NUM("access"))
UI_ACT_PROC(/obj/item/airlock_electronics, ui_act_access)
	if(locked)
		return TRUE
	// Re-validate the client-supplied access against what this user may actually program.
	var/acc = params["access"]
	if(acc in get_available_accesses(usr))
		toggle_access(acc)
	return TRUE

/obj/item/airlock_electronics/proc/toggle_access(req)
	// Copy: conf_access may be a door's interned access list (intern_access_lists()).
	conf_access = conf_access ? conf_access.Copy() : list()

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
