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

/obj/machinery/turretid/proc/isLocked(mob/user)
	if(isrobot(user) || isAI(user))
		if(ailock)
			to_chat(user, span_notice("There seems to be a firewall preventing you from accessing this device."))
			return TRUE
		else
			return FALSE

	if(isobserver(user))
		var/mob/observer/dead/D = user
		if(D.can_admin_interact())
			return FALSE
		else
			return TRUE

	if(locked)
		return TRUE

	return FALSE

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

DECLARE_EMAG(/obj/machinery/turretid, PROC_REF(on_emag), null, null)
/obj/machinery/turretid/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	to_chat(user, span_danger("You short out the turret controls' access analysis module."))
	set_emagged(TRUE)
	set_locked(FALSE)
	ailock = FALSE
	return TRUE

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

DECLARE_UI(/obj/machinery/turretid, "PortableTurret")

UI_DATA_REPLACE(/obj/machinery/turretid, "merge:ui_data_obj_machinery_turretid{locked:unknown,on:num,targetting_is_configurable:unknown,lethal:num,lethal_is_configurable:num,check_weapons:unknown,neutralize_noaccess:unknown,one_access:bool,selectedAccess:list,access_is_configurable:bool,neutralize_norecord:num,neutralize_criminals:num,neutralize_nonsynth:unknown,neutralize_all:unknown,neutralize_unidentified:unknown,neutralize_down:unknown}")

/// The computed part of /obj/machinery/turretid's window data (declared on its UI_DATA row).
/obj/machinery/turretid/proc/ui_data_obj_machinery_turretid(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

/obj/machinery/turretid/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(isLocked(ui.user))
		return FALSE
	return TRUE

UI_ACT(/obj/machinery/turretid, "power", ui_act_power)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_power)
	. = TRUE
	enabled = !enabled
	updateTurrets()

UI_ACT(/obj/machinery/turretid, "lethal", ui_act_lethal)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_lethal)
	. = TRUE
	if(lethal_is_configurable)
		lethal = !lethal
	updateTurrets()

UI_ACT(/obj/machinery/turretid, "authweapon", ui_act_authweapon)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_authweapon)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_weapons = !check_weapons
	updateTurrets()

UI_ACT(/obj/machinery/turretid, "authaccess", ui_act_authaccess)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_authaccess)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_access = !check_access
	updateTurrets()

UI_ACT(/obj/machinery/turretid, "authnorecord", ui_act_authnorecord)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_authnorecord)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_records = !check_records
	updateTurrets()

UI_ACT(/obj/machinery/turretid, "autharrest", ui_act_autharrest)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_autharrest)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_arrest = !check_arrest
	updateTurrets()

UI_ACT(/obj/machinery/turretid, "authxeno", ui_act_authxeno)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_authxeno)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_anomalies = !check_anomalies
	updateTurrets()

UI_ACT(/obj/machinery/turretid, "authsynth", ui_act_authsynth)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_authsynth)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_synth = !check_synth
	updateTurrets()

UI_ACT(/obj/machinery/turretid, "authall", ui_act_authall)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_authall)
	. = TRUE
	if(!(targetting_is_configurable))
		return FALSE
	check_all = !check_all
	updateTurrets()

UI_ACT(/obj/machinery/turretid, "authdown", ui_act_authdown)
UI_ACT_PROC(/obj/machinery/turretid, ui_act_authdown)
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

DAMAGE_REACTION(/obj/machinery/turretid, DAMAGE_EMP, PROC_REF(turretid_emp))
/// An EMP on an active control panel disables its turrets for a while and scrambles its settings.
/obj/machinery/turretid/proc/turretid_emp(datum/damage_packet/packet)
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

/obj/machinery/turretid/proc/emp_reenable()
	if(!enabled)
		enabled = TRUE
		updateTurrets()

