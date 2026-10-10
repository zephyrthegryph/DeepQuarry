/*
FIRE ALARM
*/
/obj/machinery/firealarm
	name = "fire alarm"
	desc = "<i>\"Pull this in case of emergency\"</i>. Thus, keep pulling it forever."
	icon = 'icons/obj/monitors.dmi'
	icon_state = "fire"
	layer = ABOVE_WINDOW_LAYER
	blocks_emissive = EMISSIVE_BLOCK_NONE
	vis_flags = VIS_HIDE // They have an emissive that looks bad in openspace due to their wall-mounted nature
	flags = WALL_ITEM
	var/detecting = 1.0
	var/working = 1.0
	var/time = 10.0
	var/lockdownbyai = 0
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 6
	power_channel = ENVIRON
	panel_open = FALSE
	var/seclevel
	circuit = /obj/item/circuitboard/firealarm
	var/alarms_hidden = FALSE //If the alarms from this machine are visible on consoles

	var/datum/looping_sound/alarm/fire_alarm/soundloop // Soundloops
	var/datum/looping_sound/alarm/engineering_alarm/engalarm // Soundloops
	var/datum/looping_sound/alarm/sm_critical_alarm/critalarm // Soundloops
	var/datum/looping_sound/alarm/sm_causality_alarm/causality // Soundloops

	var/firewarn = FALSE // Looping Alarms
	var/engwarn = FALSE // Looping Alarms
	var/critwarn = FALSE // Looping Alarms
	var/causalitywarn = FALSE // Looping Alarms

/// TRUE while the fire alarm's lockdown countdown runs.
/obj/machinery/firealarm/var/timing = 0
TRACKED_BRIDGED(/obj/machinery/firealarm, timing, CHANGE_MACHINE_SETTINGS)
/datum/scheduler_field_definition/obj/machinery/firealarm/timing
	of = /obj/machinery/firealarm
	field = "timing"
	channel = CHANGE_MACHINE_SETTINGS

CAPABILITIES(/obj/machinery/firealarm)
	op("firealarm_trigger", inputs(item(/obj/item), menu()), priority(OP_PRIORITY_DEFAULT - 1), label("Trigger"), needs(req_adjacent(), req_capable()), then(PROC_REF(interaction_firealarm_trigger)))
	op("firealarm_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 2), label("Use"), needs(req(PROC_REF(firealarm_use_ready), silent = TRUE)), then(PROC_REF(interaction_firealarm_use)))
	started_work(step = PROC_REF(work_step), when = nameof(timing), gate = PROC_REF(operable), wakes_on = list(nameof(timing), STAT_OPERABLE))
	owns_one(nameof(causality), /datum/looping_sound/alarm/sm_causality_alarm)
	owns_one(nameof(critalarm), /datum/looping_sound/alarm/sm_critical_alarm)
	owns_one(nameof(engalarm), /datum/looping_sound/alarm/engineering_alarm)
	owns_one(nameof(soundloop), /datum/looping_sound/alarm/fire_alarm)
	extend(/datum/act/hit/projectile, instead(then(PROC_REF(firealarm_shot))))
	extend(/datum/act/hit/emp, instead(then(PROC_REF(firealarm_emp))))
	op("use_multitool", tool(TOOL_MULTITOOL), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(multitool_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))
	op("cut_out", tool(TOOL_WIRECUTTER), priority(OP_PRIORITY_DEFAULT), wait(0), label("Cut the wires"), needs(req(PROC_REF(maintenance_panel_open), silent = TRUE)), then(PROC_REF(wires_cut_out)))

/obj/machinery/firealarm/alarms_hidden
	alarms_hidden = TRUE

/obj/machinery/firealarm/angled
	icon = 'icons/obj/wall_machines_angled.dmi'

/obj/machinery/firealarm/angled/hidden
	alarms_hidden = TRUE

/obj/machinery/firealarm/angled/offset_alarm()
	pixel_x = (dir & 3) ? 0 : (dir == 4 ? 20 : -20)
	pixel_y = (dir & 3) ? (dir == 1 ? -18 : 21) : 0

/obj/machinery/firealarm/examine()
	. = ..()
	. += "Current security level: [seclevel]"

/obj/machinery/firealarm/Initialize(mapload)
	. = ..()
	if(!pixel_x && !pixel_y)
		offset_alarm()

	if(z in using_map.contact_levels)
		set_security_level(GLOB.security_level ? get_security_level() : "green")

	rel_set(src, nameof(soundloop), new /datum/looping_sound/alarm/fire_alarm(list(src), FALSE)) // Create soundloop
	rel_set(src, nameof(engalarm), new /datum/looping_sound/alarm/engineering_alarm(list(src), FALSE)) // Create soundloop
	rel_set(src, nameof(critalarm), new /datum/looping_sound/alarm/sm_critical_alarm(list(src), FALSE)) // Create soundloop
	rel_set(src, nameof(causality), new /datum/looping_sound/alarm/sm_causality_alarm(list(src), FALSE)) // Create soundloop

// a sounding alarm is reset for its area.
/obj/machinery/firealarm/on_destroy(force)
	reset()
	..()

/obj/machinery/firealarm/proc/offset_alarm()
	pixel_x = (dir & 3) ? 0 : (dir == 4 ? 26 : -26)
	pixel_y = (dir & 3) ? (dir == 1 ? -26 : 26) : 0

DECLARE_APPEARANCE_PROC(/obj/machinery/firealarm, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/firealarm/appearance_overlays()
	. = list()

	if(panel_open)
		set_light(0)
		return .

	if(broken_now())
		icon_state = "firex"
		set_light(0)
		return .
	else if(power_lost())
		icon_state = "firep"
		set_light(0)
		return .

	var/fire_state

	. = list()
	icon_state = "fire"
	if(!detecting)
		fire_state = "fire1"
		set_light(l_range = 4, l_power = 0.9, l_color = "#ff0000")
	else
		fire_state = "fire0"
		switch(seclevel)
			if("blue")	set_light(l_range = 2, l_power = 0.25, l_color = "#1024A9")
			if("delta")	set_light(l_range = 4, l_power = 0.9, l_color = "#FF6633")
			if("green")	set_light(l_range = 2, l_power = 0.25, l_color = "#00ff00")
			if("orange")	set_light(l_range = 2, l_power = 0.25, l_color = "#ff9900")
			if("red")	set_light(l_range = 4, l_power = 0.9, l_color = "#ff0000")
			if("violet")	set_light(l_range = 2, l_power = 0.25, l_color = "#9933ff")
			if("yellow")	set_light(l_range = 2, l_power = 0.25, l_color = "#ffff00")

	. += mutable_appearance(icon, fire_state)
	. += emissive_appearance(icon, fire_state)

	if(seclevel)
		. += mutable_appearance(icon, "overlay_[seclevel]")
		. += emissive_appearance(icon, "overlay_[seclevel]")

/// Heat behaviour rule: the detector trips above 200 C.
/obj/machinery/firealarm/proc/rule_heat_alarm(datum/rule/rule)
	if(detecting)
		alarm()

/// Getting shot sets the alarm off (before the hit lands; the hit goes on).
/obj/machinery/firealarm/proc/firealarm_shot(datum/act/hit/projectile/A)
	alarm()
	return HOOK_DECLINE

/// An EMP may set the alarm off for a while (before the hit lands; the hit goes on).
/obj/machinery/firealarm/proc/firealarm_emp(datum/act/hit/emp/A)
	var/severity = A.packet.severity
	if(prob(50 / severity))
		alarm(rand(30 / severity, 60 / severity))
	return HOOK_DECLINE

/obj/machinery/firealarm/proc/interaction_firealarm_trigger(datum/act/op/A)
	add_fingerprint(A.actor)
	alarm()
	return OP_OK

/obj/machinery/firealarm/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 50, TRUE)
	set_panel_open(!panel_open)
	to_chat(user, "The wires have been [panel_open ? "exposed" : "unexposed"]")
	update_icon()
	return OP_OK

/// The wirecutters behind the open panel: the wires come out and the alarm comes off the wall.
/obj/machinery/firealarm/proc/wires_cut_out(datum/act/op/A)
	var/obj/item/tool = A.held
	act_message(A.actor, src, MSG_SELF("You have cut the wires inside %T%."), MSG_OTHERS(span_warning("%U% has cut the wires inside %T%!")))
	playsound(src, tool.usesound, 50, TRUE)
	new /obj/item/stack/cable_coil(get_turf(src), 5)
	return dismantle() ? OP_OK : OP_DECLINE

/obj/machinery/firealarm/proc/multitool_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!panel_open)
		return OP_OK
	detecting = !detecting
	act_message(user, src, MSG_SELF(span_notice("You have [detecting ? "reconnected" : "disconnected"] %T%'s detecting unit.")), \
		MSG_OTHERS(span_notice("%U% has [detecting ? "reconnected" : "disconnected"] %T%'s detecting unit!")))
	return OP_OK

/// One interval of the lockdown countdown (started_work): nothing in this fork starts it on a plain firealarm (only /obj/machinery/partyalarm has
/// a live caller), so an idle alarm costs nothing; a powered one counts down while `timing` and trips the alarm at zero. Hotspots reach an alarm
/// through its heat rule, not a poll.
/obj/machinery/firealarm/proc/work_step(datum/act/timer/A)
	if(time > 0)
		time = max(time - (MACHINE_SERVICE_INTERVAL / 10), 0)
	if(time <= 0)
		alarm()
		time = 0
		set_timing(0)
	if(detecting && (locate_within(loc, /obj/effect/hotspot)))
		alarm()
	if(!timing)
		return PROCESS_KILL

/obj/machinery/firealarm/power_change()
	. = ..()
	// A burst of power changes (every grid binding at boot) shares one pending settle.
	if(!after_pending(src, "power_settle"))
		after(src, rand(0 SECONDS,1.5 SECONDS), PROC_REF(power_change_settle), key = "power_settle")

/obj/machinery/firealarm/proc/firealarm_use_ready(datum/act/op/A)
	return (!A.actor.stat && operable()) ? null : MSG(req_failed)


/obj/machinery/firealarm/proc/interaction_firealarm_use(datum/act/op/A)
	var/mob/user = A.actor

	add_fingerprint(user)
	var/area/zone = get_area(src)
	if(zone.fire)
		reset(user)
	else
		alarm(0, user)
	return OP_OK

/obj/machinery/firealarm/proc/reset(mob/user)
	if(!(working))
		return
	var/area/area = get_area(src)
	for(var/obj/machinery/firealarm/FA in area_contents_of_type(area, /obj/machinery/firealarm))
		GLOB.fire_alarm.clearAlarm(src.loc, FA)
		FA.soundloop?.stop() // Mapped alarms may be destroyed before Initialize creates this.
		FA.firewarn = FALSE // Soundloop Fix
	update_icon()
	if(user)
		log_game("[user] reset a fire alarm at [COORD(src)]")

/obj/machinery/firealarm/proc/alarm(duration = 0, mob/user)
	if(!(working))
		return
	var/area/area = get_area(src)
	if(!firewarn && !alarms_hidden)
		GLOB.global_announcer.autosay("Tripped [area]", "Fire Alarm Monitor", DEPARTMENT_ENGINEERING)
	for(var/obj/machinery/firealarm/FA in area_contents_of_type(area, /obj/machinery/firealarm))
		GLOB.fire_alarm.triggerAlarm(loc, FA, duration, hidden = alarms_hidden)
		FA.soundloop?.start() // Mapped alarms may be triggered before Initialize creates this.
		FA.firewarn = TRUE // Soundloop Fix
	update_icon()
	// playsound(src, 'sound/machines/airalarm.ogg', 25, 0, 4, volume_channel = VOLUME_CHANNEL_ALARMS) // Disable as per soundloop
	if(user)
		log_game("[user] triggered a fire alarm at [COORD(src)]")

/obj/machinery/firealarm/proc/set_security_level(newlevel)
	if(seclevel != newlevel)
		seclevel = newlevel
		update_icon()

/obj/machinery/partyalarm
	name = "\improper PARTY BUTTON"
	desc = "Cuban Pete is in the house!"
	icon = 'icons/obj/monitors.dmi'
	icon_state = "fire0"
	var/detecting = 1.0
	var/working = 1.0
	var/time = 10.0
	var/timing = 0.0
	var/lockdownbyai = 0
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 6

// TGUI migration. PartyAlarm.tsx handles both clear-text
// (humans/AI) and scrambled (everyone else) display via a data flag.

/obj/machinery/partyalarm/proc/interaction_partyalarm_use(datum/act/op/A)
	var/mob/user = A.actor
	if(user.stat || !operable())
		return OP_OK
	user.set_machine(src)
	tgui_interact(user)
	return OP_OK

CAPABILITIES(/obj/machinery/partyalarm)
	interface("PartyAlarm", title = "Party Button")
	op("reset", ui_act("reset"), then(PROC_REF(ui_act_reset)))
	op("alarm", ui_act("alarm"), then(PROC_REF(ui_act_alarm)))
	op("time", ui_act("time", arg("value", num())), then(PROC_REF(ui_act_time)))
	op("tp", ui_act("tp", arg("value", num())), then(PROC_REF(ui_act_tp)))
	extend(TAG_UI, needs(req(PROC_REF(button_usable))))
	op("partyalarm_use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_partyalarm_use)))

MSG_DEF_SELF(partyalarm/unusable, "You can't work the button.")

/// The button answers someone who is awake, and only while it works.
/obj/machinery/partyalarm/proc/button_usable(datum/act/op/A)
	var/mob/user = A.actor
	return (!user.stat && operable()) ? null : MSG(partyalarm/unusable)

/obj/machinery/partyalarm/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	var/area/here = get_area(src)
	data["party_on"] = !!here?.party
	data["timing"] = !!timing
	data["scrambled"] = !(ishuman(user) || istype(user, /mob/living/silicon/ai))
	data["time"] = time
	return data

/obj/machinery/partyalarm/proc/reset()
	if(!(working))
		return
	var/area/A = get_area(src)
	ASSERT(isarea(A))
	A.partyreset()
	return

/obj/machinery/partyalarm/proc/alarm()
	if(!(working))
		return
	var/area/A = get_area(src)
	ASSERT(isarea(A))
	A.partyalert()
	return

/obj/machinery/partyalarm/proc/ui_act_reset(datum/act/op/A)
	reset()
	return TRUE

/obj/machinery/partyalarm/proc/ui_act_alarm(datum/act/op/A)
	alarm()
	return TRUE

/obj/machinery/partyalarm/proc/ui_act_time(datum/act/op/A, value)
	timing = value
	return TRUE

/obj/machinery/partyalarm/proc/ui_act_tp(datum/act/op/A, value)
	var/tp = value
	time += tp
	time = min(max(round(time), 0), 120)
	return TRUE

/obj/machinery/firealarm/proc/power_change_settle()
	update_icon()
	// Looping Red/Violet/Orange Alarms
	if(!soundloop)
		return
	if(!operable()) // Are we broken or out of power?
		soundloop.stop() // Stop the loop once we're out of power
		engalarm.stop() // Stop these bc we're out of power
		critalarm.stop() // Stop these, out of power
		causality.stop() // etc etc
	else
		if(firewarn)
			soundloop.start()
		if(engwarn)
			engalarm.start()
		if(critwarn)
			critalarm.start()
		if(causalitywarn)
			causality.start()
