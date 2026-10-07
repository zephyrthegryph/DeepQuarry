////////////////////////
//Turret Control Panel//
////////////////////////

// A turret control panel is declared (doc/rewrite/final_api.html section 16.3, conversion_guide.md): it takes over the turrets of its area (a link
// between the panel and the area, so a turret asks its area whether a panel controls it) and hands them its settings whenever one changes. The ID
// lock (lock()) gates its window, an emag strips the lock and the silicons' firewall (ailock), and an electromagnetic pulse knocks it out for a
// while (emp_disable()): while it is down its turrets are told to stand down, and they come back with it.

/area
	/// The turret control panels of this area (a link: each panel's control_area names it). A turret in the area with one obeys it.
	var/list/turret_controls

MSG_DEF_SELF(turretid/firewall, "There seems to be a firewall preventing you from accessing this device.")
MSG_DEF(turretid/shorted, "You short out the turret controls' access analysis module.", "")

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
	/// The area whose turrets it controls (a link). A mapper names it by its path or its name in `control_area_name`; else the panel's own area.
	var/area/control_area
	var/control_area_name

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

TRACKED(/obj/machinery/turretid, enabled)
TRACKED(/obj/machinery/turretid, lethal)
TRACKED(/obj/machinery/turretid, check_arrest)
TRACKED(/obj/machinery/turretid, check_records)
TRACKED(/obj/machinery/turretid, check_weapons)
TRACKED(/obj/machinery/turretid, check_access)
TRACKED(/obj/machinery/turretid, check_anomalies)
TRACKED(/obj/machinery/turretid, check_synth)
TRACKED(/obj/machinery/turretid, check_all)
TRACKED(/obj/machinery/turretid, check_down)
TRACKED(/obj/machinery/turretid, ailock)

/obj/machinery/turretid/stun
	enabled = TRUE
	icon_state = "control_stun"

/obj/machinery/turretid/lethal
	enabled = TRUE
	lethal = TRUE
	icon_state = "control_kill"

CAPABILITIES(/obj/machinery/turretid)
	machine_basics(repair = NONE)
	links(/obj/machinery/turretid::control_area, /area::turret_controls, b_many = TRUE)
	lock(starts_locked = TRUE, alt = FALSE)
	emag(then(PROC_REF(on_emag)), say = MSG(turretid/shorted))
	emp_disable(list(6 SECONDS, 60 SECONDS))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(scramble_settings)))
	on_change(STAT_OPERABLE, ANY, then(PROC_REF(push_settings)))
	after_init(0, then(PROC_REF(push_settings)))

	section(window, "The panel's window and its buttons")
	interface("PortableTurret")
	extend(TAG_UI, needs(req_window_usable(remote = PROC_REF(firewall_open), remote_because = MSG(turretid/firewall))))
	extend(TAG_UI, then(PROC_REF(push_settings)))
	op("power", ui_act(), toggles(nameof(enabled)))
	op("lethal", ui_act(), toggles(nameof(lethal), when = nameof(lethal_is_configurable)))
	op("authweapon", ui_act(), toggles(nameof(check_weapons), when = nameof(targetting_is_configurable)))
	op("authaccess", ui_act(), toggles(nameof(check_access), when = nameof(targetting_is_configurable)))
	op("authnorecord", ui_act(), toggles(nameof(check_records), when = nameof(targetting_is_configurable)))
	op("autharrest", ui_act(), toggles(nameof(check_arrest), when = nameof(targetting_is_configurable)))
	op("authxeno", ui_act(), toggles(nameof(check_anomalies), when = nameof(targetting_is_configurable)))
	op("authsynth", ui_act(), toggles(nameof(check_synth), when = nameof(targetting_is_configurable)))
	op("authall", ui_act(), toggles(nameof(check_all), when = nameof(targetting_is_configurable)))
	op("authdown", ui_act(), toggles(nameof(check_down), when = nameof(targetting_is_configurable)))
	// a silicon's ctrl-click switches the turrets, its alt-click their lethal mode, over its link and under the window's rules
	op("remote_power", remote(), gesture(GESTURE_CTRL), label("Toggle the turrets"), toggles(nameof(enabled)))
	op("remote_lethal", remote(), gesture(GESTURE_ALT), label("Toggle lethal mode"), toggles(nameof(lethal), when = nameof(lethal_is_configurable)))
	extend("remote_power", needs(req_silicon_or_admin(), req_unlocked_for_actor(), req_window_usable(remote = PROC_REF(firewall_open), remote_because = MSG(turretid/firewall))), then(PROC_REF(push_settings)))
	extend("remote_lethal", needs(req_silicon_or_admin(), req_unlocked_for_actor(), req_window_usable(remote = PROC_REF(firewall_open), remote_because = MSG(turretid/firewall))), then(PROC_REF(push_settings)))

// ALLOW(init/INSTANCE_STATE): the area a mapper named (by path or by name) is found once, when the panel is placed, and linked
/obj/machinery/turretid/Initialize(mapload)
	. = ..()
	var/area/target = get_area(src)
	if(ispath(control_area))
		target = locate(control_area)
	else if(control_area_name)
		target = area_named(control_area_name) || target
	rel_set(src, nameof(control_area), istype(target) ? target : null)

/// The area of that name, or null: areas are made with the map and keep their names, so the index is built once, on the first ask.
/proc/area_named(name)
	var/static/list/by_name
	if(!by_name)
		by_name = list()
		for(var/area/A in world) // the one walk of the map's areas, once, to index them by name
			if(A.name && !by_name[A.name])
				by_name[A.name] = A
	return by_name[name]

/// The firewall (ailock) is down: a silicon over its link may work the window (req_window_usable() asks this only of a remote user).
/obj/machinery/turretid/proc/firewall_open(datum/act/op/A)
	return !ailock

/// The emag: the ID lock and the firewall are gone (and the lock cannot be engaged again: the panel is subverted).
/obj/machinery/turretid/proc/on_emag(datum/act/op/A)
	cap_key_set(src, LOCK_LOCKED, FALSE, null)
	set_ailock(FALSE)
	return OP_OK

/obj/machinery/turretid/ui_data(datum/act/eval/A)
	return list(
		"locked" = lock_locked(src),
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

/// Hands the turrets of its area the panel's settings: on, lethal and every target check (a panel a pulse knocked out tells them to stand down).
/obj/machinery/turretid/proc/push_settings(datum/act/A)
	if(!istype(control_area))
		return OP_OK
	var/datum/turret_checks/TC = new
	TC.enabled = enabled && stat_value(src, STAT_OPERABLE) // a panel knocked out (a pulse) or unpowered tells its turrets to stand down
	TC.lethal = lethal
	TC.check_synth = check_synth
	TC.check_access = check_access
	TC.check_records = check_records
	TC.check_arrest = check_arrest
	TC.check_weapons = check_weapons
	TC.check_anomalies = check_anomalies
	TC.check_all = check_all
	TC.check_down = check_down
	for(var/obj/machinery/porta_turret/aTurret as anything in REGISTRY_MEMBERS(REGISTRY_TURRETS))
		if(get_area(aTurret) == control_area)
			aTurret.setState(TC)
	return OP_OK

/// The look: off without power, else the mode it sets (standby, stun, kill), with its light.
/obj/machinery/turretid/draw(datum/look/look)
	..()
	if(power_lost())
		look.state("control_off")
	else if(enabled)
		look.state(lethal ? "control_kill" : "control_stun")
		look.light(1.5, 1, lethal ? "#990000" : "#FF9900")
	else
		look.state("control_standby")
		look.light(1.5, 1, "#003300")

/// A pulse on an active panel scrambles its targets (the outage is emp_disable()'s, and push_settings() tells the turrets).
/obj/machinery/turretid/proc/scramble_settings(datum/act/A)
	if(enabled)
		turret_targets_scramble(src)
