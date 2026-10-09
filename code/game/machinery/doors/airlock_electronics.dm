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

TRACKED(/obj/item/airlock_electronics, locked)
TRACKED(/obj/item/airlock_electronics, one_access)
TRACKED(/obj/item/airlock_electronics, last_configurator)

MSG_DEF_SELF(airlock_electronics/hardened, "You don't appear to be able to bypass this hardened device!")
MSG_DEF_SELF(airlock_electronics/logged_out, "It is locked: log in first.")
MSG_DEF_SELF(airlock_electronics/cant_use, "You can't use that right now.")
MSG_DEF(airlock_electronics/emagged, "You remove the access restrictions on %T%!", "")

// The device is its own window: held and used on itself it opens the programming interface; its buttons are ops.

CAPABILITIES(/obj/item/airlock_electronics)
	interface("AirlockElectronics", title = "Airlock Electronics", input = in_hand())
	emag(list(needs(req(PROC_REF(not_hardened), because = MSG(airlock_electronics/hardened))), then(PROC_REF(emag_effect))), say = MSG(airlock_electronics/emagged))
	op("login", ui_act("login"), then(PROC_REF(ui_login)))
	op("logout", ui_act("logout"), needs(req(PROC_REF(logged_in), because = MSG(airlock_electronics/logged_out))), then(PROC_REF(ui_logout)))
	op("one_access", ui_act("one_access"), needs(req(PROC_REF(logged_in), because = MSG(airlock_electronics/logged_out))), then(PROC_REF(ui_one_access)))
	op("access_all", ui_act("access_all"), needs(req(PROC_REF(logged_in), because = MSG(airlock_electronics/logged_out))), then(PROC_REF(ui_access_all)))
	op("access", ui_act("access", arg("access", int(0, 999))), needs(req(PROC_REF(logged_in), because = MSG(airlock_electronics/logged_out))), then(PROC_REF(ui_access)))
	extend(TAG_UI, needs(req(PROC_REF(ui_user_ok), because = MSG(airlock_electronics/cant_use))))
	extend("ui_open", when(req(PROC_REF(user_may_open))))

/// Only a person or a cyborg takes the device in hand to program it.
/obj/item/airlock_electronics/proc/user_may_open(datum/act/op/A)
	return ishuman(A.actor) || istype(A.actor, /mob/living/silicon/robot)

/obj/item/airlock_electronics/proc/ui_user_ok(datum/act/op/A)
	var/mob/user = A.actor
	return !user.stat && !user.restrained() && (ishuman(user) || istype(user, /mob/living/silicon))

/obj/item/airlock_electronics/proc/logged_in(datum/act/A)
	return !locked

/obj/item/airlock_electronics/proc/not_hardened(datum/act/A)
	return !secure // ALLOW(reads): the hardened kind is a different type; the flag never changes

/// A cryptographic sequencer removes the access restrictions (a hardened device cannot be bypassed).
/obj/item/airlock_electronics/proc/emag_effect(datum/act/op/A)
	emagged = 1
	return OP_OK

/// The computed part of the window data.
/obj/item/airlock_electronics/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
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

/obj/item/airlock_electronics/proc/ui_login(datum/act/op/A)
	var/mob/user = A.actor
	if(emagged || issilicon(user))
		set_locked(0)
		set_last_configurator(user.name)
	else if(isliving(user))
		var/obj/item/card/id/id
		if(ishuman(user))
			var/mob/living/carbon/human/H = user
			id = H.get_idcard()
			if(id && check_access(id))
				set_locked(0)
				set_last_configurator(id.registered_name)
		if(locked)
			var/obj/item/I = user.get_active_hand()
			id = I?.GetID()
			if(id && check_access(id))
				set_locked(0)
				set_last_configurator(id.registered_name)
	return OP_OK

/obj/item/airlock_electronics/proc/ui_logout(datum/act/op/A)
	set_locked(1)
	return OP_OK

/obj/item/airlock_electronics/proc/ui_one_access(datum/act/op/A)
	set_one_access(!one_access)
	return OP_OK

/obj/item/airlock_electronics/proc/ui_access_all(datum/act/op/A)
	// Clears all access requirements; only allow users who may program any access.
	var/list/available = get_available_accesses(A.actor)
	if(length(available) && length(available) >= length(SSaccess.get_all_station_access()))
		conf_access = null
		changed(src)
	return OP_OK

/obj/item/airlock_electronics/proc/ui_access(datum/act/op/A, access)
	// Re-validate the client-supplied access against what this user may actually program.
	if(access in get_available_accesses(A.actor))
		toggle_access(access)
	return OP_OK

/obj/item/airlock_electronics/proc/toggle_access(req)
	// Copy: conf_access may be a door's interned access list (intern_access_lists()).
	var/list/access = conf_access ? conf_access.Copy() : list()

	if (!(req in access))
		access += req
	else
		access -= req
		if (!access.len)
			access = null
	conf_access = access
	changed(src)

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
