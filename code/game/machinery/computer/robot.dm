/obj/machinery/computer/robotics
	name = "robotics control console"
	desc = "Used to remotely lockdown or detonate linked cyborgs."
	icon_keyboard = "tech_key"
	icon_screen = "robot"
	light_color = "#a97faa"
	req_access = list(ACCESS_ROBOTICS)
	circuit = /obj/item/circuitboard/robotics
	var/safety = 1

MSG_DEF_SELF(robotics/access_denied, "Access denied.")
MSG_DEF_SELF(robotics/cannot_hack, "You cannot hack that.")
MSG_DEF_SELF(robotics/silicon_denied, "Access Denied (silicon detected)")

/obj/machinery/computer/robotics/proc/interaction_use(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return OP_OK
	tgui_interact(user)
	return OP_OK

/obj/machinery/computer/robotics/proc/is_authenticated(mob/user)
	if(!istype(user))
		return FALSE
	if(isobserver(user))
		var/mob/observer/dead/D = user
		if(D.can_admin_interact())
			return TRUE
	if(allowed(user))
		return TRUE
	return FALSE

/**
 * Does this borg show up in the console
 *
 * Returns TRUE if a robot will show up in the console
 * Returns FALSE if a robot will not show up in the console
 * Arguments:
 * * R - The [mob/living/silicon/robot] to be checked
 */
/obj/machinery/computer/robotics/proc/console_shows(mob/living/silicon/robot/R)
	if(!istype(R))
		return FALSE
	if(istype(R, /mob/living/silicon/robot/drone))
		return FALSE
	if(R.scrambledcodes)
		return FALSE
	if(!AreConnectedZLevels(get_z(src), get_z(R)))
		return FALSE
	return TRUE

/**
 * Check if a user can send a lockdown/detonate command to a specific borg
 *
 * Returns TRUE if a user can send the command (does not guarantee it will work)
 * Returns FALSE if a user cannot
 * Arguments:
 * * user - The [mob/user] to be checked
 * * R - The [mob/living/silicon/robot] to be checked
 * * telluserwhy - Bool of whether the user should be sent a to_chat message if they don't have access
 */
/obj/machinery/computer/robotics/proc/can_control(mob/user, mob/living/silicon/robot/R, telluserwhy = FALSE)
	if(!istype(user))
		return FALSE
	if(!console_shows(R))
		return FALSE
	if(isAI(user))
		if(R.connected_ai != user)
			if(telluserwhy)
				to_chat(user, span_warning("AIs can only control cyborgs which are linked to them."))
			return FALSE
	if(isrobot(user))
		if(R != user)
			if(telluserwhy)
				to_chat(user, span_warning("Cyborgs cannot control other cyborgs."))
			return FALSE
	return TRUE

/**
 * Check if the user is the right kind of entity to be able to hack borgs
 *
 * Returns TRUE if a user is a traitor AI, or aghost
 * Returns FALSE otherwise
 * Arguments:
 * * user - The [mob/user] to be checked
 */
/obj/machinery/computer/robotics/proc/can_hack_any(mob/user)
	if(!istype(user))
		return FALSE
	if(isobserver(user))
		var/mob/observer/dead/D = user
		if(D.can_admin_interact())
			return TRUE
	if(!isAI(user))
		return FALSE
	var/mob/living/original = user.mind.original_character // ALLOW(reads): who may hack is asked when the question opens and again when it is answered, never cached
	return (user.mind.special_role && (original && original == user)) // ALLOW(reads): who may hack is asked when the question opens and again when it is answered, never cached

/**
 * Check if the user is allowed to hack a specific borg
 *
 * Returns TRUE if a user can hack the specific cyborg
 * Returns FALSE if a user cannot
 * Arguments:
 * * user - The [mob/user] to be checked
 * * R - The [mob/living/silicon/robot] to be checked
 */
/obj/machinery/computer/robotics/proc/can_hack(mob/user, mob/living/silicon/robot/R)
	if(!can_hack_any(user))
		return FALSE
	if(!istype(R))
		return FALSE
	if(R.emagged)
		return FALSE
	if(R.connected_ai != user)
		return FALSE
	return TRUE

CAPABILITIES(/obj/machinery/computer/robotics)
	interface("RoboticsControlConsole")
	op("arm", ui_act("arm"), needs(req_actor_kind(/mob/living/silicon, not = TRUE, because = MSG(robotics/silicon_denied))), then(PROC_REF(ui_act_arm)))
	op("nuke", ui_act("nuke"), needs(req_actor_kind(/mob/living/silicon, not = TRUE, because = MSG(robotics/silicon_denied))), then(PROC_REF(ui_act_nuke)))
	op("killbot", ui_act("killbot", arg("ref")), then(PROC_REF(ui_act_killbot)))
	op("stopbot", ui_act("stopbot", arg("ref")), then(PROC_REF(ui_act_stopbot)))
	op("hackbot", ui_act("hackbot", arg("ref")), needs(req(PROC_REF(hack_possible), because = MSG(robotics/cannot_hack))), asks(/datum/prompt/yes_no, fields = list("title" = "Hack?", "question" = "Really hack this cyborg? This cannot be undone.")), then(PROC_REF(ui_act_hackbot)))
	extend(TAG_UI, needs(req(PROC_REF(ui_authenticated), because = MSG(robotics/access_denied))))
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))
	op("robotics_console_robot_use", remote(), when(req_actor_kind(/mob/living/silicon/robot)), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(robotics_console_robot_use)))

/obj/machinery/computer/robotics/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["safety"] = safety
	data["auth"] = is_authenticated(user)
	data["can_hack"] = can_hack_any(user)
	data["cyborgs"] = list()
	for(var/mob/living/silicon/robot/R in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(!console_shows(R))
			continue
		var/area/cyborg_area = get_area(R)
		var/turf/T = get_turf(R)
		var/list/cyborg_data = list(
			name = R.name,
			ref = REF(R),
			locked_down = R.lockcharge,
			locstring = "[cyborg_area.name] ([T.x], [T.y])",
			status = R.stat,
			health = round(R.vitality() * 100, 0.1),
			charge = R.cell ? round(R.cell.percent()) : null,
			cell_capacity = R.cell ? R.cell.maxcharge : null,
			module = R.module ? R.module.name : "No Module Detected",
			synchronization = R.connected_ai,
			is_hacked =  R.connected_ai && R.emagged,
			emagged = R.emagged,
			hackable = can_hack(user, R),
		)
		data["cyborgs"] += list(cyborg_data)
	data["show_detonate_all"] = (data["auth"] && length(data["cyborgs"]) > 0 && ishuman(user))
	return data

/// Every button needs the operator to be authenticated (the old window guard).
/obj/machinery/computer/robotics/proc/ui_authenticated(datum/act/op/A)
	return is_authenticated(A.actor)

/obj/machinery/computer/robotics/proc/ui_act_arm(datum/act/op/A)
	safety = !safety
	to_chat(A.actor, span_notice("You [safety ? "disarm" : "arm"] the emergency self destruct."))
	. = TRUE

/obj/machinery/computer/robotics/proc/ui_act_nuke(datum/act/op/A)
	if(safety)
		to_chat(A.actor, span_danger("Self-destruct aborted - safety active"))
		return
	message_admins(span_notice("[key_name_admin(A.actor)] detonated all cyborgs!"))
	log_game(span_notice("[key_name(A.actor)] detonated all cyborgs!"))
	for(var/mob/living/silicon/robot/R in REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(istype(R, /mob/living/silicon/robot/drone))
			continue
		// Ignore antagonistic cyborgs
		if(R.scrambledcodes)
			continue
		to_chat(R, span_danger("Self-destruct command received."))
		if(R.connected_ai)
			to_chat(R.connected_ai, "<br><br>[span_alert("ALERT - Cyborg detonation detected: [R.name]")]<br>")
		R.self_destruct()
	. = TRUE

/obj/machinery/computer/robotics/proc/ui_act_killbot(datum/act/op/A, ref)
	var/mob/living/silicon/robot/R = ui_ref(ref, null, /mob/living/silicon/robot)
	if(!can_control(A.actor, R, TRUE))
		return
	if(R.mind && R.mind.special_role && R.emagged)
		to_chat(R, span_userdanger("Extreme danger!  Termination codes detected.  Scrambling security codes and automatic AI unlink triggered."))
		R.ResetSecurityCodes()
		. = TRUE
		return
	var/turf/T = get_turf(R)
	message_admins(span_notice("[key_name_admin(A.actor)] detonated [key_name_admin(R)] ([ADMIN_COORDJMP(T)])!"))
	log_game(span_notice("[key_name(A.actor)] detonated [key_name(R)]!"))
	to_chat(R, span_danger("Self-destruct command received."))
	if(R.connected_ai)
		to_chat(R.connected_ai, "<br><br>[span_alert("ALERT - Cyborg detonation detected: [R.name]")]<br>")
	R.self_destruct()
	. = TRUE

/obj/machinery/computer/robotics/proc/ui_act_stopbot(datum/act/op/A, ref)
	if(isrobot(A.actor))
		to_chat(A.actor, span_danger("Access Denied."))
		return
	var/mob/living/silicon/robot/R = ui_ref(ref, null, /mob/living/silicon/robot)
	if(!can_control(A.actor, R, TRUE))
		return
	message_admins(span_notice("[ADMIN_LOOKUPFLW(A.actor)] [!R.lockcharge ? "locked down" : "released"] [ADMIN_LOOKUPFLW(R)]!"))
	log_game("[key_name(A.actor)] [!R.lockcharge ? "locked down" : "released"] [key_name(R)]!")
	R.SetLockdown(!R.lockcharge)
	to_chat(R, "[!R.lockcharge ? span_notice("Your lockdown has been lifted!") : span_alert("You have been locked down!")]")
	if(R.connected_ai)
		to_chat(R.connected_ai, "[!R.lockcharge ? span_notice("NOTICE - Cyborg lockdown lifted") : span_alert("ALERT - Cyborg lockdown detected")]: <a href='byond://?src=[REF(R.connected_ai)];track=[html_encode(R.name)]'>[R.name]</a><br>")
	. = TRUE

/// The cyborg the window button named, when the console shows it.
/obj/machinery/computer/robotics/proc/hack_target(datum/act/op/A)
	return ui_ref(A.args["ref"], null, /mob/living/silicon/robot)

/obj/machinery/computer/robotics/proc/hack_possible(datum/act/op/A)
	return can_hack(A.actor, hack_target(A))

/obj/machinery/computer/robotics/proc/ui_act_hackbot(datum/act/op/A, ref)
	var/datum/prompt/answer = A.answer
	if(!answer?.value)
		return OP_OK
	var/mob/living/silicon/robot/R = ui_ref(ref, null, /mob/living/silicon/robot)
	if(!can_hack(A.actor, R))
		return OP_REFUSED
	log_game("[key_name(A.actor)] emagged [key_name(R)] using robotic console!")
	message_admins(span_notice("[key_name_admin(A.actor)] emagged [key_name_admin(R)] using robotic console!"))
	R.set_emagged(TRUE)
	to_chat(R, span_notice("Failsafe protocols overridden. New tools available."))
	return OP_OK

// A cyborg with access interfaces remotely as the AI does (FALSE: the robot adapter's default); without it, only by hand from next to it.

/obj/machinery/computer/robotics/proc/robotics_console_robot_use(datum/act/op/A)
	var/mob/user = A.actor
	if(allowed(user))
		return OP_DECLINE
	if(Adjacent(user))
		attack_hand(user)
	return OP_OK
