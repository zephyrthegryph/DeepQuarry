/obj/item/transfer_valve
	name = "tank transfer valve"
	desc = "Regulates the transfer of air between two tanks"
	icon = 'icons/obj/assemblies.dmi'
	icon_state = "valve_1"
	var/obj/item/tank/tank_one
	var/obj/item/tank/tank_two
	var/obj/item/assembly/attached_device
	var/mob/attacher
	var/valve_open = 0
	COOLDOWN_DECLARE(toggle)

/// Old attackby: attach a tank (two at most) or an unsecured assembly to the valve controls.
/obj/item/transfer_valve/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/item = A.held
	var/turf/location = get_turf(src) // For admin logs
	if(istype(item, /obj/item/tank))
		if(tank_one && tank_two)
			to_chat(user, span_warning("There are already two tanks attached, remove one first."))
			return OP_OK

		if(!tank_one)
			if(!move_into(src, nameof(src.tank_one), item, user))
				return OP_OK
			to_chat(user, span_notice("You attach the tank to the transfer valve."))
		else if(!tank_two)
			if(!move_into(src, nameof(src.tank_two), item, user))
				return OP_OK
			to_chat(user, span_notice("You attach the tank to the transfer valve."))
			message_admins("[key_name_admin(user)] attached both tanks to a transfer valve. [ADMIN_JMP(location)]")
			log_game("[key_name_admin(user)] attached both tanks to a transfer valve.")

		SStgui.update_uis(src) // update all UIs attached to src
		return OP_OK
//TODO: Have this take an assemblyholder
	else if(isassembly(item))
		var/obj/item/assembly/AS = item
		if(AS.secured)
			to_chat(user, span_notice("The device is secured."))
			return OP_OK
		if(attached_device)
			to_chat(user, span_warning("There is already an device attached to the valve, remove it first."))
			return OP_OK
		if(!move_into(src, nameof(src.attached_device), AS, user))
			return OP_OK
		to_chat(user, span_notice("You attach the [item] to the valve controls and secure it."))
		rel_set(AS, nameof(AS.holder), src)
		AS.toggle_secure()	//securing it redraws the bomb it sits in (the holder watches its parts).

		GLOB.bombers += "[key_name(user)] attached a [item] to a transfer valve."
		message_admins("[key_name_admin(user)] attached a [item] to a transfer valve. [ADMIN_JMP(location)]")
		log_game("[key_name_admin(user)] attached a [item] to a transfer valve.")
		rel_set(src, nameof(attacher), user)
		SStgui.update_uis(src) // update all UIs attached to src
		return OP_OK
	return OP_DECLINE

/obj/item/transfer_valve/HasProximity(turf/T, WF, old_loc)
	if(isnull(WF))
		return
	var/atom/movable/AM = WF
	if(isnull(AM))
		log_runtime("DEBUG: HasProximity called without reference on [src].")
	attached_device?.HasProximity(T, WF, old_loc)

/obj/item/transfer_valve/Moved(old_loc, direction, forced)
	. = ..()
	if(isturf(old_loc))
		unsense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity), center = old_loc)
	if(isturf(loc))
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity))

/// Old attack_self: the valve's window.
/obj/item/transfer_valve/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	tgui_interact(user)
	return OP_OK

CAPABILITIES(/obj/item/transfer_valve)
	interface("TransferValve", state = nameof(GLOB.tgui_inventory_state))
	without("ui_open")
	op("tankone", ui_act("tankone"), then(PROC_REF(ui_act_tankone)))
	op("tanktwo", ui_act("tanktwo"), then(PROC_REF(ui_act_tanktwo)))
	op("toggle", ui_act("toggle"), then(PROC_REF(ui_act_toggle)))
	op("device", ui_act("device"), then(PROC_REF(ui_act_device)))
	op("remove_device", ui_act("remove_device"), then(PROC_REF(ui_act_remove_device)))
	op("attach", inputs(item(/obj/item/tank), item(/obj/item/assembly)), label("Attach"), then(PROC_REF(interaction_item)))
	op("view", in_hand(), then(PROC_REF(interaction_self)))

/obj/item/transfer_valve/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["valve"] = valve_open
	var/list/merged_1 = ui_data_obj_item_transfer_valve(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/transfer_valve's window data.
/obj/item/transfer_valve/proc/ui_data_obj_item_transfer_valve(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["tank_one"] = tank_one ? tank_one.name : null
	data["tank_two"] = tank_two ? tank_two.name : null
	data["attached_device"] = attached_device ? attached_device.name : null
	return data

/obj/item/transfer_valve/proc/ui_act_tankone(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	remove_tank(tank_one)
	if(.)
		add_fingerprint(user)

/obj/item/transfer_valve/proc/ui_act_tanktwo(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	remove_tank(tank_two)
	if(.)
		add_fingerprint(user)

/obj/item/transfer_valve/proc/ui_act_toggle(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	toggle_valve()
	if(.)
		add_fingerprint(user)

/obj/item/transfer_valve/proc/ui_act_device(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	if(attached_device)
		attached_device.attack_self(user)
	if(.)
		add_fingerprint(user)

/obj/item/transfer_valve/proc/ui_act_remove_device(datum/act/op/A)
	var/mob/user = A.actor
	. = TRUE
	if(attached_device)
		attached_device.forceMove(get_turf(src))
		rel_clear(attached_device, nameof(/client::holder))
		rel_take(src, nameof(/obj/item/transfer_valve::attached_device))
	if(.)
		add_fingerprint(user)

/obj/item/transfer_valve/proc/process_activation(obj/item/D)
	if(COOLDOWN_FINISHED(src, toggle))
		COOLDOWN_START(src, toggle, 5 SECONDS)
		toggle_valve()

/// The valve with its tanks and the device attached to it.
/obj/item/transfer_valve/draw(datum/look/look)
	..()
	look.watch(tank_one)
	look.watch(tank_two)
	look.watch(attached_device)
	if(!tank_one && !tank_two && !attached_device)
		look.state("valve_1")
		return
	look.state("valve")

	if(tank_one)
		look.overlay("[tank_one.icon_state]")
	if(tank_two)
		look.underlay(look_overlay_image(icon, "[tank_two.icon_state]", pixel_x = -13))
	if(attached_device)
		look.overlay("device")

/obj/item/transfer_valve/proc/remove_tank(obj/item/tank/T)
	if(tank_one == T)
		split_gases()
		rel_take(src, nameof(tank_one))
	else if(tank_two == T)
		split_gases()
		rel_take(src, nameof(tank_two))
	else
		return

	// A valve in nullspace (or a tank being deleted) has nowhere to put it.
	var/turf/drop = get_turf(src)
	if(drop && !QDELETED(T))
		T.forceMove(drop)

/obj/item/transfer_valve/proc/merge_gases()
	if(valve_open)
		return
	tank_two.air_contents.set_volume(tank_two.air_contents.return_volume() + tank_one.air_contents.return_volume())
	var/datum/gas_mixture/temp
	temp = tank_one.air_contents.remove_ratio(1)
	tank_two.air_contents.merge(temp)
	valve_open = 1

/obj/item/transfer_valve/proc/split_gases()
	if(!valve_open)
		return

	valve_open = 0

	if(QDELETED(tank_one) || QDELETED(tank_two))
		return

	var/ratio1 = tank_one.air_contents.return_volume()/tank_two.air_contents.return_volume()
	var/datum/gas_mixture/temp
	temp = tank_two.air_contents.remove_ratio(ratio1)
	tank_one.air_contents.merge(temp)
	tank_two.air_contents.set_volume(tank_two.air_contents.return_volume() - tank_one.air_contents.return_volume())


	/*
	Exadv1: I know this isn't how it's going to work, but this was just to check
	it explodes properly when it gets a signal (and it does).
	*/

/obj/item/transfer_valve/proc/toggle_valve()
	if(!valve_open && (tank_one && tank_two))
		var/turf/bombturf = get_turf(src)
		var/area/A = get_area(bombturf)

		var/attacher_name = ""
		if(!attacher())
			attacher_name = "Unknown"
		else
			attacher_name = "[attacher().name]([attacher().ckey])"

		var/log_str = "Bomb valve opened in <A href='byond://?_src_=holder;[HrefToken(TRUE)];adminplayerobservecoodjump=1;X=[bombturf.x];Y=[bombturf.y];Z=[bombturf.z]'>[A.name]</a> "
		log_str += "with [attached_device ? attached_device : "no device"] attacher: [attacher_name]"

		if(attacher())
			log_str += ADMIN_QUE(attacher())

		var/mob/mob = get_mob_by_key(forensic_data?.get_lastprint())
		var/last_touch_info = ""
		if(mob)
			last_touch_info = ADMIN_QUE(mob)

		log_str += " Last touched by: [forensic_data?.get_lastprint()][last_touch_info]"
		GLOB.bombers += log_str
		message_admins(log_str, 0, 1)
		log_game(log_str)
		merge_gases()

	else if(valve_open==1 && (tank_one && tank_two))
		split_gases()


// this doesn't do anything but the timer etc. expects it to be here
// eventually maybe have it update icon to show state (timer, prox etc.) like old bombs
/obj/item/transfer_valve/proc/c_state()
	return

/obj/item/transfer_valve/ownership()
	. = ..()
	. += owns(nameof(tank_one), policy = OWN_CONTAINED)
	. += owns(nameof(tank_two), policy = OWN_CONTAINED)
	. += owns(nameof(attached_device), policy = OWN_CONTAINED)

/// Relation view: attacher (reads null once it is gone).
/obj/item/transfer_valve/proc/attacher() as /mob
	return attacher
