////////////////////////
//Turret Control Panel//
////////////////////////

/area
	// Turrets use this list to see if individual power/lethal settings are allowed
	var/list/turret_controls

/obj/machinery/turretid
	name = "turret control panel"
	desc = "Used to control a room's automated defenses."
	icon = 'icons/obj/machines/turret_control.dmi'
	icon_state = "control_standby"
	anchored = TRUE
	density = FALSE
	unacidable = TRUE
	var/enabled = FALSE
	var/lethal = FALSE
	var/lethal_is_configurable = TRUE
	locked = TRUE
	var/area/control_area //can be area name, path or nothing.

	var/targetting_is_configurable = TRUE // if false, you cannot change who this turret attacks via its UI
	var/check_arrest = TRUE	//checks if the perp is set to arrest
	var/check_records = TRUE	//checks if a security record exists at all
	var/check_weapons = FALSE	//checks if it can shoot people that have a weapon they aren't authorized to have
	var/check_access = TRUE	//if this is active, the turret shoots everything that does not meet the access requirements
	var/check_anomalies = TRUE	//checks if it can shoot at unidentified lifeforms (ie xenos)
	var/check_synth = FALSE 	//if active, will shoot at anything not an AI or cyborg
	var/check_all = FALSE		//If active, will shoot at anything.
	var/check_down = TRUE		//If active, won't shoot laying targets.
	var/ailock = FALSE 	//Silicons cannot use this

	var/syndicate = FALSE

	req_access = list(ACCESS_AI_UPLOAD)

/obj/machinery/turretid/stun
	enabled = TRUE
	icon_state = "control_stun"

/obj/machinery/turretid/lethal
	enabled = TRUE
	lethal = TRUE
	icon_state = "control_kill"

/// Phase 2: leaves its area's turret controls.
/obj/machinery/turretid/lifecycle_dematerialize()
	. = ..()
	var/area/A = control_area
	if(istype(A))
		LAZYREMOVE(A.turret_controls, src)

/obj/machinery/turretid/Initialize(mapload)
	if(!control_area)
		control_area = get_area(src)
	else if(ispath(control_area))
		control_area = locate(control_area)
	else if(istext(control_area))
		for(var/area/A in world)
			if(A.name && A.name==control_area)
				control_area = A
				break

	if(control_area)
		var/area/A = control_area
		if(istype(A))
			LAZYADD(A.turret_controls, src)
		else
			control_area = null

	power_change() //Checks power and initial settings
	. = ..()

MSG_DEF_SELF(turretid/panel_locked, "The controls are locked.")
MSG_DEF_SELF(turretid/firewall, "There seems to be a firewall preventing you from accessing this device.")

/// Why the panel's controls refuse `user` (a message type), or null when they answer: reads only.
/// Why `user` acting under `authority` may not work the panel, or null. Over a link (AUTH_REMOTE_ACCESS) only the firewall stops it; in person, the lock.
/obj/machinery/turretid/proc/lock_refusal(mob/user, authority = actor_authority(user))
	if(authority & AUTH_REMOTE_ACCESS)
		return ailock ? /datum/msg/turretid/firewall : null // ALLOW(reads): the firewall is read when a button is pressed, never from a cached menu

	if(isobserver(user))
		var/mob/observer/dead/D = user
		return D.can_admin_interact() ? null : /datum/msg/turretid/panel_locked

	return locked ? /datum/msg/turretid/panel_locked : null

/obj/machinery/turretid/proc/isLocked(mob/user)
	var/why = lock_refusal(user)
	if(why == /datum/msg/turretid/firewall)
		to_chat(user, span_notice("There seems to be a firewall preventing you from accessing this device."))
	return !!why

/obj/machinery/turretid/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/turretid_toggle_lock,
		/datum/interaction/machine_hand/ungated/turretid_open_ui,
	)
	..()

/// The old attackby: toggled the lock with an ID/pda, else fell through to ..().
/datum/interaction/machine_item/turretid_toggle_lock
	id = "turretid_toggle_lock"
	name = "Toggle lock"
	category = INTERACTION_CAT_LOCK
	held_type = /obj/item
	effect = /obj/machinery/turretid/proc/interaction_toggle_lock

/obj/machinery/turretid/proc/interaction_toggle_lock(mob/user, obj/item/W, datum/interaction/interaction)
	if(has_stat(BROKEN))
		return TRUE

	if(istype(W, /obj/item/card/id)||istype(W, /obj/item/pda))
		if(allowed(user))
			if(emagged)
				to_chat(user, span_notice("The turret control is unresponsive."))
			else
				set_locked(!locked)
				to_chat(user, span_notice("You [ locked ? "lock" : "unlock"] the panel."))
		return TRUE
	return FALSE

/obj/machinery/turretid/proc/on_emag(datum/act/op/A)
	to_chat(A.actor, span_danger("You short out the turret controls' access analysis module."))
	set_emagged(TRUE)
	set_locked(FALSE)
	ailock = FALSE
	return OP_OK

/obj/machinery/turretid
	silicon_use = SILICON_USE_UI

/// The old attack_hand: never called ..(), just opened the UI.
/datum/interaction/machine_hand/ungated/turretid_open_ui
	id = "turretid_open_ui"
	name = "Use"
	effect = /obj/machinery/turretid/proc/interaction_open_ui_impl

/obj/machinery/turretid/proc/interaction_open_ui_impl(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/machinery/turretid)
	interface("PortableTurret")
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("lethal", ui_act("lethal"), then(PROC_REF(ui_act_lethal)))
	op("authweapon", ui_act("authweapon"), then(PROC_REF(ui_act_authweapon)))
	op("authaccess", ui_act("authaccess"), then(PROC_REF(ui_act_authaccess)))
	op("authnorecord", ui_act("authnorecord"), then(PROC_REF(ui_act_authnorecord)))
	op("autharrest", ui_act("autharrest"), then(PROC_REF(ui_act_autharrest)))
	op("authxeno", ui_act("authxeno"), then(PROC_REF(ui_act_authxeno)))
	op("authsynth", ui_act("authsynth"), then(PROC_REF(ui_act_authsynth)))
	op("authall", ui_act("authall"), then(PROC_REF(ui_act_authall)))
	op("authdown", ui_act("authdown"), then(PROC_REF(ui_act_authdown)))
	extend(TAG_UI, needs(req(PROC_REF(controller_unlocked), because = PROC_REF(controller_lock_reason))))
	// a silicon's ctrl-click switches the turrets, its alt-click their lethal mode, over its link and under the window's rules
	op("remote_power", remote(), gesture(GESTURE_CTRL), label("Toggle the turrets"), then(PROC_REF(ui_act_power)))
	op("remote_lethal", remote(), gesture(GESTURE_ALT), label("Toggle lethal mode"), then(PROC_REF(ui_act_lethal)))
	extend(list("remote_power", "remote_lethal"), needs(req(PROC_REF(remote_link_allowed), because = MSG(turretid/panel_locked)),
		req(PROC_REF(controller_unlocked), because = PROC_REF(controller_lock_reason))))
	emag(then(PROC_REF(on_emag)))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(turretid_emp))))

/// The window answers someone who has the panel's access.
/obj/machinery/turretid/proc/controller_unlocked(datum/act/op/A)
	return isnull(lock_refusal(A.actor, A.authority))

/// Why the window refuses someone.
/obj/machinery/turretid/proc/controller_lock_reason(datum/act/op/A)
	return lock_refusal(A.actor, A.authority) || /datum/msg/turretid/panel_locked

/obj/machinery/turretid/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list(
		"locked" = isLocked(user), // does the current user have access?
		"on" = enabled,
		"targetting_is_configurable" = targetting_is_configurable,
		"lethal" = lethal,
		"lethal_is_configurable" = lethal_is_configurable,
		"check_weapons" = check_weapons,
		"neutralize_noaccess" = check_access,
		"one_access" = FALSE,
		"selectedAccess" = list(),
		"access_is_configurable" = FALSE,
		"neutralize_norecord" = check_records,
		"neutralize_criminals" = check_arrest,
		"neutralize_nonsynth" = check_synth,
		"neutralize_all" = check_all,
		"neutralize_unidentified" = check_anomalies,
		"neutralize_down" = check_down,
	)
	return data


/obj/machinery/turretid/proc/ui_act_power(datum/act/op/A)
	. = TRUE
	enabled = !enabled
	updateTurrets()

/obj/machinery/turretid/proc/ui_act_lethal(datum/act/op/A)
	. = TRUE
	if(lethal_is_configurable)
		lethal = !lethal
	updateTurrets()

/obj/machinery/turretid/proc/ui_act_authweapon(datum/act/op/A)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_weapons = !check_weapons
	updateTurrets()

/obj/machinery/turretid/proc/ui_act_authaccess(datum/act/op/A)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_access = !check_access
	updateTurrets()

/obj/machinery/turretid/proc/ui_act_authnorecord(datum/act/op/A)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_records = !check_records
	updateTurrets()

/obj/machinery/turretid/proc/ui_act_autharrest(datum/act/op/A)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_arrest = !check_arrest
	updateTurrets()

/obj/machinery/turretid/proc/ui_act_authxeno(datum/act/op/A)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_anomalies = !check_anomalies
	updateTurrets()

/obj/machinery/turretid/proc/ui_act_authsynth(datum/act/op/A)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_synth = !check_synth
	updateTurrets()

/obj/machinery/turretid/proc/ui_act_authall(datum/act/op/A)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_all = !check_all
	updateTurrets()

/obj/machinery/turretid/proc/ui_act_authdown(datum/act/op/A)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_down = !check_down
	updateTurrets()

/obj/machinery/turretid/proc/updateTurrets()
	var/datum/turret_checks/TC = new
	TC.enabled = enabled
	TC.lethal = lethal
	TC.check_synth = check_synth
	TC.check_access = check_access
	TC.check_records = check_records
	TC.check_arrest = check_arrest
	TC.check_weapons = check_weapons
	TC.check_anomalies = check_anomalies
	TC.check_all = check_all
	TC.ailock = ailock

	if(istype(control_area))
		for(var/obj/machinery/porta_turret/aTurret in control_area)
			aTurret.setState(TC)

	update_icon()

/obj/machinery/turretid/power_change()
	. = ..()
	updateTurrets()

DECLARE_APPEARANCE_PROC(/obj/machinery/turretid, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/turretid/appearance_overlays()
	. = list()
	. += ..()
	if(has_stat(NOPOWER))
		icon_state = "control_off"
		set_light(0)
	else if(enabled)
		if(lethal)
			icon_state = "control_kill"
			set_light(1.5, 1,"#990000")
		else
			icon_state = "control_stun"
			set_light(1.5, 1,"#FF9900")
	else
		icon_state = "control_standby"
		set_light(1.5, 1,"#003300")

/// An EMP on an active control panel disables its turrets for a while and scrambles its settings (before the hit lands; the hit goes on).
/obj/machinery/turretid/proc/turretid_emp(datum/act/hit/emp/A)
	if(enabled)
		//if the turret is on, the EMP no matter how severe disables the turret for a while
		//and scrambles its settings, with a slight chance of having an emag effect

		check_arrest = pick(0, 1)
		check_records = pick(0, 1)
		check_weapons = pick(0, 1)
		check_access = pick(0, 0, 0, 0, 1)	// check_access is a pretty big deal, so it's least likely to get turned on
		check_anomalies = pick(0, 1)

		enabled = FALSE
		updateTurrets()

		after(src, rand(6 SECONDS, 60 SECONDS), PROC_REF(emp_reenable))
	return HOOK_DECLINE

/obj/machinery/turretid/proc/emp_reenable()
	if(!enabled)
		enabled = TRUE
		updateTurrets()


// A cyborg with access interfaces remotely as the AI does (FALSE: the robot adapter's default); without it, only by hand from next to it.
EXTEND_INTERACTIONS(/obj/machinery/turretid, INTERACT_ROBOT("Use", PROC_REF(turretid_robot_use)))

/obj/machinery/turretid/proc/turretid_robot_use(mob/user, obj/item/held, datum/interaction/interaction)
	if(allowed(user))
		return FALSE
	if(Adjacent(user))
		attack_hand(user)
	return TRUE
