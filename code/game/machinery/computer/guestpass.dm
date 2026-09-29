/////////////////////////////////////////////
//Guest pass ////////////////////////////////
/////////////////////////////////////////////
/obj/item/card/id/guest
	name = "guest pass"
	desc = "Allows temporary access to station areas."
	icon_state = "guest"
	initial_sprite_stack = list()
	light_color = "#0099ff"

	var/temp_access = list() //to prevent agent cards stealing access as permanent
	EXPIRY_DECLARE(expiration_time)
	var/expired = 0
	var/reason = "NOT SPECIFIED"
	special_handling = TRUE

/obj/item/card/id/guest/update_icon()
	return

/obj/item/card/id/guest/GetAccess()
	if(EXPIRY_EXPIRED(src, expiration_time, CLOCK_WORLD))
		return access
	else
		return temp_access

/obj/item/card/id/guest/examine(mob/user)
	. = ..()
	if(EXPIRY_ACTIVE(src, expiration_time, CLOCK_WORLD))
		. += span_notice("This pass expires at [worldtime2stationtime(expiration_time)].")
	else
		. += span_warning("It expired at [worldtime2stationtime(expiration_time)].")

/obj/item/card/id/guest/id_read_effect(mob/user, obj/item/held, datum/interaction/interaction)
	if(!Adjacent(user))
		return //Too far to read
	if(EXPIRY_EXPIRED(src, expiration_time, CLOCK_WORLD))
		to_chat(user, span_notice("This pass expired at [worldtime2stationtime(expiration_time)]."))
	else
		to_chat(user, span_notice("This pass expires at [worldtime2stationtime(expiration_time)]."))

	to_chat(user, span_notice("It grants access to following areas:"))
	for (var/A in temp_access)
		to_chat(user, span_notice("[SSaccess.get_access_desc(A)]."))
	to_chat(user, span_notice("Issuing reason: [reason]."))
	return

// Replaces the card's own flash: the old override ran both and flashed the pass twice.
EXTEND_INTERACTIONS(/obj/item/card/id/guest, INTERACT_USE_AS(I_HELP, "Show", PROC_REF(interaction_guest_pass_show)), INTERACT_USE_AS(I_DISARM, "Show", PROC_REF(interaction_guest_pass_show)), INTERACT_USE_AS(I_GRAB, "Show", PROC_REF(interaction_guest_pass_show)), INTERACT_USE_AS(I_HURT, "Deactivate", PROC_REF(interaction_guest_pass_deactivate), REQ_BECAUSE(REQ_NOT(REQ_FIELD_EQ("icon_state", "guest-invalid")), "this guest pass is already deactivated")))

/// Old attack_self outside combat mode: flash the pass.
/obj/item/card/id/guest/proc/interaction_guest_pass_show(mob/living/user, obj/item/held, datum/interaction/interaction)
	act_message(user, null, MSG_SELF("You flash your ID card: [icon2html(src, user.client)] [src.name]. The assignment on the card: [src.assignment]"), \
		MSG_OTHERS("%U% shows you: [icon2html(src,viewers(src))] [src.name]. The assignment on the card: [src.assignment]"))

	src.add_fingerprint(user)

/// Old attack_self in combat mode: deactivate the pass.
/obj/item/card/id/guest/proc/interaction_guest_pass_deactivate(mob/living/user, obj/item/held, datum/interaction/interaction)
	om_ask(user, /datum/om/prompt/confirm, PROC_REF(deactivation_confirmed), title = "Confirm Deactivation", message = "Do you really want to deactivate this guest pass? (you can't reactivate it)", ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/card/id/guest/proc/deactivation_confirmed(datum/om/prompt/confirm/ask)
	var/mob/living/user = ask.answerer
	if(icon_state != "guest-invalid")
		//rip guest pass </3
		act_message(user, src, others = span_infoplain(span_bold("%U%") + "deactivates %T%."))
		icon_state = "guest-invalid"
		update_icon()
		EXPIRY_STAMP(src, expiration_time, CLOCK_WORLD)
		expired = 1

/obj/item/card/id/guest/Initialize(mapload)
	. = ..()
	update_icon()

/// The pass turns red when its expiry lapses, however it was made (terminal, admin spawn, map).
EXPIRY_ON_LAPSE(/obj/item/card/id/guest, expiration_time, CLOCK_WORLD, PROC_REF(pass_lapsed))

/obj/item/card/id/guest/proc/pass_lapsed()
	if(expired)
		return
	visible_message(span_warning("\The [src] flashes a few times before turning red."))
	icon_state = "guest-invalid"
	update_icon()
	expired = 1

/////////////////////////////////////////////
//Guest pass terminal////////////////////////
/////////////////////////////////////////////

/obj/machinery/computer/guestpass
	name = "guest pass terminal"
	desc = "Used to print temporary passes for people. Handy!"
	icon_state = "guest"
	layer = ABOVE_WINDOW_LAYER
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	icon_keyboard = null
	icon_screen = "pass"
	density = FALSE
	circuit = /obj/item/circuitboard/guestpass
	flags = WALL_ITEM

	var/obj/item/card/id/giver
	var/list/accesses
	var/giv_name = "NOT SPECIFIED"
	var/reason = "NOT SPECIFIED"
	var/duration = 5

	var/list/internal_log
	mode = 0  // 0 - making pass, 1 - viewing logs

/obj/machinery/computer/guestpass/Initialize(mapload)
	. = ..()
	uid = "[rand(100,999)]-G[rand(10,99)]"


/obj/machinery/computer/guestpass/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/guestpass_reject_guest_card,
		/datum/interaction/machine_item/guestpass_insert_id,
		/datum/interaction/machine_verb/guestpass_eject_id,
		/datum/interaction/machine_hand/open_ui,
	)
	..()

/// A guest pass itself is refused.
/datum/interaction/machine_item/guestpass_reject_guest_card
	id = "guestpass_reject_guest_card"
	name = "Insert ID"
	held_type = /obj/item/card/id/guest
	effect = /obj/machinery/computer/guestpass/proc/interaction_reject_guest_card

/obj/machinery/computer/guestpass/proc/interaction_reject_guest_card(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_warning("The guest pass terminal denies to accept the guest pass."))
	return TRUE

/// Insert an ID card to use as the source of grantable accesses.
/datum/interaction/machine_item/guestpass_insert_id
	id = "guestpass_insert_id"
	name = "Insert ID"
	held_type = /obj/item/card/id
	also_requires = list(REQ_TARGET_STATE(/obj/machinery/computer/guestpass/proc/can_insert_id))
	effect = /obj/machinery/computer/guestpass/proc/interaction_insert_id

/// Requirement: checking for power here so crowbar and screwdriver and stuff still work.
/obj/machinery/computer/guestpass/proc/can_insert_id(mob/user, atom/target, obj/item/held)
	if(has_stat(NOPOWER))
		return "the terminal refuses your ID as it is unpowered"
	return TRUE

/obj/machinery/computer/guestpass/proc/interaction_insert_id(mob/user, obj/item/held, datum/interaction/interaction)
	if(!giver && user.unEquip(held))
		held.forceMove(src)
		own_set(src, "giver", held)
		SStgui.update_uis(src)
	else if(giver)
		to_chat(user, span_warning("There is already ID card inside."))
	return TRUE

/datum/interaction/machine_verb/guestpass_eject_id
	id = "guestpass_eject_id"
	name = "Eject ID Card"
	category = INTERACTION_CAT_EJECT
	effect = /obj/machinery/computer/guestpass/proc/interaction_eject_id

/obj/machinery/computer/guestpass/proc/interaction_eject_id(mob/user, obj/item/held, datum/interaction/interaction)
	if(giver)
		to_chat(user, span_notice("You remove \the [giver] from \the [src]."))
		giver.forceMove(get_turf(src))
		if(!user.get_active_hand() && ishuman(user))
			user.put_in_hands(giver)
		else
			giver.forceMove(src.loc)
		own_take(src, "giver")
		LAZYCLEARLIST(accesses)
	else
		to_chat(user, span_warning("There is nothing to remove from the console."))
	return TRUE

DECLARE_UI(/obj/machinery/computer/guestpass, "GuestPass")

UI_DATA(/obj/machinery/computer/guestpass, "giver", "giveName=giv_name:text", "reason:text", "duration:num", "uid", "merge:ui_data_obj_machinery_computer_guestpass{access:unknown,area:list,mode:num,log:bool}")

/// The computed part of /obj/machinery/computer/guestpass's window data (declared on its UI_DATA row).
/obj/machinery/computer/guestpass/proc/ui_data_obj_machinery_computer_guestpass(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/area_list = list()

	data["access"] = null
	if(giver && giver.GetAccess())
		data["access"] = giver.GetAccess()
		for (var/A in giver.GetAccess())
			if(A in accesses)
				area_list.Add(list(list("area" = A, "area_name" = SSaccess.get_access_desc(A), "on" = 1)))
			else
				area_list.Add(list(list("area" = A, "area_name" = SSaccess.get_access_desc(A), "on" = null)))
	data["area"] = area_list

	data["mode"] = mode
	data["log"] = (internal_log || list())

	return data

UI_ACT(/obj/machinery/computer/guestpass, "mode", ui_act_mode, UI_ARG_NUM("mode"))
UI_ACT_PROC(/obj/machinery/computer/guestpass, ui_act_mode)
	set_mode(params["mode"])
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/guestpass, "giv_name", ui_act_giv_name)
UI_ACT_PROC(/obj/machinery/computer/guestpass, ui_act_giv_name)
	om_ask(ui.user, /datum/om/prompt/text, PROC_REF(pass_name_entered), title = "Name", message = "Person pass is issued to", default = giv_name, requires = PROMPT_USABLE)
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/guestpass, "reason", ui_act_reason)
UI_ACT_PROC(/obj/machinery/computer/guestpass, ui_act_reason)
	om_ask(ui.user, /datum/om/prompt/text, PROC_REF(pass_reason_entered), title = "Reason", message = "Reason why pass is issued", default = reason, requires = PROMPT_USABLE)
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/guestpass, "duration", ui_act_duration)
UI_ACT_PROC(/obj/machinery/computer/guestpass, ui_act_duration)
	om_ask(ui.user, /datum/om/prompt/number, PROC_REF(pass_duration_entered), title = "Duration", message = "Duration (in minutes) during which pass is valid (up to 360 minutes).", max = 360, min = 0, requires = PROMPT_USABLE)
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/guestpass, "access", ui_act_access, UI_ARG_NUM("access"))
UI_ACT_PROC(/obj/machinery/computer/guestpass, ui_act_access)
	var/A = params["access"]
	if(A in accesses)
		LAZYREMOVE(accesses, A)
	else
		if(A in giver.GetAccess())	//Let's make sure the ID card actually has the access.
			LAZYADD(accesses, A)
		else
			to_chat(ui.user, span_warning("Invalid selection, please consult technical support if there are any issues."))
			log_admin("[key_name_admin(ui.user)] tried selecting an invalid guest pass terminal option.")
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/guestpass, "id", ui_act_id)
UI_ACT_PROC(/obj/machinery/computer/guestpass, ui_act_id)
	if(giver)
		if(ishuman(ui.user))
			giver.forceMove(ui.user.loc)
			if(!ui.user.get_active_hand())
				ui.user.put_in_hands(giver)
			own_take(src, "giver")
		else
			giver.forceMove(src.loc)
			own_take(src, "giver")
		LAZYCLEARLIST(accesses)
	else
		var/obj/item/I = ui.user.get_active_hand()
		if(istype(I, /obj/item/card/id) && ui.user.unEquip(I))
			I.forceMove(src)
			own_set(src, "giver", I)
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/guestpass, "print", ui_act_print)
UI_ACT_PROC(/obj/machinery/computer/guestpass, ui_act_print)
	var/dat = "<h3>Activity log of guest pass terminal #[uid]</h3><br>"
	for (var/entry in internal_log)
		dat += "[entry]<br><hr>"
	var/obj/item/paper/P = new/obj/item/paper( loc )
	P.name = "activity log"
	P.info = dat
	add_fingerprint(ui.user)
	return TRUE

UI_ACT(/obj/machinery/computer/guestpass, "issue", ui_act_issue)
UI_ACT_PROC(/obj/machinery/computer/guestpass, ui_act_issue)
	if(giver)
		var/number = add_zero("[rand(0,9999)]", 4)
		var/entry = "\[[stationtime2text()]\] Pass #[number] issued by [giver.registered_name] ([giver.assignment]) to [giv_name]. Reason: [reason]. Grants access to following areas: "
		for (var/i=1 to length(accesses))
			var/A = LAZYACCESS(accesses, i)
			if(A)
				var/area = SSaccess.get_access_desc(A)
				entry += "[i > 1 ? ", [area]" : "[area]"]"
		entry += ". Expires at [worldtime2stationtime(world.time + duration*10*60)]."
		LAZYADD(internal_log, entry)

		var/obj/item/card/id/guest/pass = new(src.loc)
		pass.temp_access = LAZYCOPY(accesses)
		pass.registered_name = giv_name
		EXPIRY_SET(pass, expiration_time, duration MINUTES, CLOCK_WORLD)
		pass.reason = reason
		pass.name = "guest pass #[number]"
	else
		to_chat(ui.user, span_warning("Cannot issue pass without issuing ID."))
	add_fingerprint(ui.user)
	return TRUE

/obj/machinery/computer/guestpass/proc/pass_name_entered(datum/om/prompt/text/ask)
	var/nam = sanitizeName(ask.text)
	if(nam)
		giv_name = nam
		SStgui.update_uis(src)

/obj/machinery/computer/guestpass/proc/pass_reason_entered(datum/om/prompt/text/ask)
	var/reas = ask.text
	if(reas)
		reason = reas
		SStgui.update_uis(src)

/obj/machinery/computer/guestpass/proc/pass_duration_entered(datum/om/prompt/number/ask)
	var/dur = ask.number
	var/mob/user = ask.answerer
	if(!dur)
		return
	if(dur > 0 && dur <= 360)
		duration = dur
		SStgui.update_uis(src)
	else
		to_chat(user, span_warning("Invalid duration."))

OWN(/obj/machinery/computer/guestpass, giver, OWN_CONTAINED)
