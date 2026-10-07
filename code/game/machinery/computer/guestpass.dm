/////////////////////////////////////////////
//Guest pass ////////////////////////////////
/////////////////////////////////////////////
/obj/item/card/id/guest
	name = "guest pass"
	desc = "Allows temporary access to station areas."
	icon_state = "guest"
	initial_sprite_stack = list()
	light_color = "#0099ff"

	var/list/temp_access //to prevent agent cards stealing access as permanent
	EXPIRY_DECLARE(expiration_time)
	var/expired = 0
	var/reason = "NOT SPECIFIED"
	special_handling = TRUE

APPEARANCE_NONE(/obj/item/card/id/guest)

/obj/item/card/id/guest/GetAccess()
	if(EXPIRY_EXPIRED(src, expiration_time, CLOCK_WORLD))
		return access
	else
		LAZYINITLIST(temp_access)
		return temp_access

/obj/item/card/id/guest/examine(mob/user)
	. = ..()
	if(EXPIRY_ACTIVE(src, expiration_time, CLOCK_WORLD))
		. += span_notice("This pass expires at [worldtime2stationtime(expiration_time)].")
	else
		. += span_warning("It expired at [worldtime2stationtime(expiration_time)].")

/obj/item/card/id/guest/id_read_effect(mob/user)
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
CAPABILITIES(/obj/item/card/id/guest)
	op("show_pass", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), stance(I_HELP, I_DISARM, I_GRAB), label("Show"), then(PROC_REF(interaction_guest_pass_show)))
	op("deactivate_pass", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), stance(I_HURT), label("Deactivate"), needs(req(PROC_REF(deactivation_allowed), because = "this guest pass is already deactivated or no longer carried")),
		asks(/datum/prompt/yes_no, fields = list("title" = "Confirm Deactivation", "question" = "Do you really want to deactivate this guest pass? (you can't reactivate it)", "timeout" = 0)), then(PROC_REF(interaction_guest_pass_deactivate)))

/// Old attack_self outside combat mode: flash the pass.
/obj/item/card/id/guest/proc/interaction_guest_pass_show(datum/act/op/A)
	var/mob/living/user = A.actor
	act_message(user, null, MSG_SELF("You flash your ID card: [icon2html(src, user.client)] [src.name]. The assignment on the card: [src.assignment]"), \
		MSG_OTHERS("%U% shows you: [icon2html(src,viewers(src))] [src.name]. The assignment on the card: [src.assignment]"))

	src.add_fingerprint(user)

/// Old attack_self in combat mode: deactivate the pass.
/obj/item/card/id/guest/proc/deactivation_allowed(datum/act/op/A)
	var/mob/living/user = A.actor
	return istype(user) && loc == user && !user.incapacitated() && icon_state != "guest-invalid"

/obj/item/card/id/guest/proc/interaction_guest_pass_deactivate(datum/act/op/A)
	if(!A.answer?.value)
		return OP_OK
	var/mob/living/user = A.actor
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

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/machinery/computer/guestpass/proc/roll_uid(datum/roller/R)
	return "[R.number(100, 999)]-G[R.number(10, 99)]"

/obj/machinery/computer/guestpass/proc/interaction_reject_guest_card(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_warning("The guest pass terminal denies to accept the guest pass."))
	return TRUE

/// Requirement: checking for power here so crowbar and screwdriver and stuff still work.
/obj/machinery/computer/guestpass/proc/can_insert_id(mob/user, atom/target, obj/item/held)
	if(power_lost())
		return "the terminal refuses your ID as it is unpowered"
	return TRUE

/// Requirement (was REQ_* can_insert_id): the legacy check answers TRUE to pass.
/obj/machinery/computer/guestpass/proc/can_insert_id_holds(datum/act/op/A)
	var/answer = can_insert_id(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_insert_id_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/computer/guestpass/proc/can_insert_id_refusal(datum/act/op/A)
	var/answer = can_insert_id(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/machinery/computer/guestpass/proc/interaction_insert_id(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(!giver && move_into(src, nameof(src.giver), held, user))
		SStgui.update_uis(src)
	else if(giver)
		to_chat(user, span_warning("There is already ID card inside."))
	return TRUE

/// Requirement (was REQ_* dq_actor_can_act): the legacy check answers TRUE to pass.
/obj/machinery/computer/guestpass/proc/dq_actor_can_act_holds(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why dq_actor_can_act_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/computer/guestpass/proc/dq_actor_can_act_refusal(datum/act/op/A)
	var/answer = dq_actor_can_act(A.actor, src, A.held)
	return istext(answer) ? answer : "you can't do that right now"

/obj/machinery/computer/guestpass/proc/interaction_eject_id(datum/act/op/A)
	var/mob/user = A.actor
	if(giver)
		to_chat(user, span_notice("You remove \the [giver] from \the [src]."))
		giver.forceMove(get_turf(src))
		if(!user.get_active_hand() && ishuman(user))
			user.put_in_hands(giver)
		else
			giver.forceMove(src.loc)
		rel_take(src, nameof(giver))
		LAZYCLEARLIST(accesses)
	else
		to_chat(user, span_warning("There is nothing to remove from the console."))
	return TRUE

CAPABILITIES(/obj/machinery/computer/guestpass)
	interface("GuestPass")
	op("mode", ui_act("mode", arg("mode", num())), then(PROC_REF(ui_act_mode)))
	op("giv_name", ui_act("giv_name"), asks(/datum/prompt/text, fields = list("title" = "Name", "question" = "Person pass is issued to", "default" = nameof(giv_name))), then(PROC_REF(ui_act_giv_name)))
	op("reason", ui_act("reason"), asks(/datum/prompt/text, fields = list("title" = "Reason", "question" = "Reason why pass is issued", "default" = nameof(reason))), then(PROC_REF(ui_act_reason)))
	op("duration", ui_act("duration"), asks(/datum/prompt/number, fields = list("title" = "Duration", "question" = "Duration (in minutes) during which pass is valid (up to 360 minutes).", "min_value" = 0, "max_value" = 360)), then(PROC_REF(ui_act_duration)))
	op("access", ui_act("access", arg("access", num())), then(PROC_REF(ui_act_access)))
	op("id", ui_act("id"), then(PROC_REF(ui_act_id)))
	op("print", ui_act("print"), then(PROC_REF(ui_act_print)))
	op("issue", ui_act("issue"), then(PROC_REF(ui_act_issue)))
	rolls(nameof(uid), PROC_REF(roll_uid))
	op("reject_guest_card", item(/obj/item/card/id/guest), priority(OP_PRIORITY_DEFAULT - 1), label("Insert ID"), then(PROC_REF(interaction_reject_guest_card)))
	op("insert_id", item(/obj/item/card/id), priority(OP_PRIORITY_DEFAULT - 1), label("Insert ID"), needs(req(PROC_REF(can_insert_id_holds), because = PROC_REF(can_insert_id_refusal))), then(PROC_REF(interaction_insert_id)))
	op("eject_id", menu(), priority(OP_PRIORITY_DEFAULT - 1), label("Eject ID Card"), needs(req_adjacent(), req_capable(), req(PROC_REF(dq_actor_can_act_holds), because = PROC_REF(dq_actor_can_act_refusal))), then(PROC_REF(interaction_eject_id)))

/obj/machinery/computer/guestpass/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["giver"] = giver
	data["giveName"] = giv_name
	data["reason"] = reason
	data["duration"] = duration
	data["uid"] = uid

	var/list/area_list = list()

	data["access"] = null
	if(giver && giver.GetAccess())
		data["access"] = giver.GetAccess()
		for (var/acc in giver.GetAccess())
			if(acc in accesses)
				area_list.Add(list(list("area" = acc, "area_name" = SSaccess.get_access_desc(acc), "on" = 1)))
			else
				area_list.Add(list(list("area" = acc, "area_name" = SSaccess.get_access_desc(acc), "on" = null)))
	data["area"] = area_list

	data["mode"] = mode
	data["log"] = (internal_log || list())

	return data

/obj/machinery/computer/guestpass/proc/ui_act_mode(datum/act/op/A, new_mode)
	set_mode(new_mode)
	add_fingerprint(A.actor)
	return TRUE

/obj/machinery/computer/guestpass/proc/ui_act_giv_name(datum/act/op/A)
	add_fingerprint(A.actor)
	var/datum/prompt/R = A.answer
	var/nam = sanitizeName(R?.value)
	if(nam)
		giv_name = nam
	return TRUE

/obj/machinery/computer/guestpass/proc/ui_act_reason(datum/act/op/A)
	add_fingerprint(A.actor)
	var/datum/prompt/R = A.answer
	if(R?.value)
		reason = R.value
	return TRUE

/obj/machinery/computer/guestpass/proc/ui_act_duration(datum/act/op/A)
	add_fingerprint(A.actor)
	var/datum/prompt/R = A.answer
	var/dur = R?.value
	if(dur > 0 && dur <= 360)
		duration = dur
	return TRUE

/obj/machinery/computer/guestpass/proc/ui_act_access(datum/act/op/A, access)
	var/selected = access
	if(selected in accesses)
		LAZYREMOVE(accesses, selected)
	else
		if(selected in giver?.GetAccess())	//Let's make sure the ID card actually has the access.
			LAZYADD(accesses, selected)
		else
			to_chat(A.actor, span_warning("Invalid selection, please consult technical support if there are any issues."))
			log_admin("[key_name_admin(A.actor)] tried selecting an invalid guest pass terminal option.")
	add_fingerprint(A.actor)
	return TRUE

/obj/machinery/computer/guestpass/proc/ui_act_id(datum/act/op/A)
	if(giver)
		if(ishuman(A.actor))
			giver.forceMove(A.actor.loc)
			if(!A.actor.get_active_hand())
				A.actor.put_in_hands(giver)
			rel_take(src, nameof(/obj/machinery/computer/guestpass::giver))
		else
			giver.forceMove(src.loc)
			rel_take(src, nameof(/obj/machinery/computer/guestpass::giver))
		LAZYCLEARLIST(accesses)
	else
		var/obj/item/I = A.actor.get_active_hand()
		if(istype(I, /obj/item/card/id))
			move_into(src, nameof(src.giver), I, A.actor)
	add_fingerprint(A.actor)
	return TRUE

/obj/machinery/computer/guestpass/proc/ui_act_print(datum/act/op/A)
	var/dat = "<h3>Activity log of guest pass terminal #[uid]</h3><br>"
	for (var/entry in internal_log)
		dat += "[entry]<br><hr>"
	var/obj/item/paper/P = new/obj/item/paper( loc )
	P.name = "activity log"
	P.info = dat
	add_fingerprint(A.actor)
	return TRUE

/obj/machinery/computer/guestpass/proc/ui_act_issue(datum/act/op/A)
	if(giver)
		var/number = add_zero("[rand(0,9999)]", 4)
		var/entry = "\[[stationtime2text()]\] Pass #[number] issued by [giver.registered_name] ([giver.assignment]) to [giv_name]. Reason: [reason]. Grants access to following areas: "
		for (var/i=1 to length(accesses))
			var/granted = LAZYACCESS(accesses, i)
			if(granted)
				var/area = SSaccess.get_access_desc(granted)
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
		to_chat(A.actor, span_warning("Cannot issue pass without issuing ID."))
	add_fingerprint(A.actor)
	return TRUE

/obj/machinery/computer/guestpass/ownership()
	. = ..()
	. += owns(nameof(giver), policy = OWN_CONTAINED)
