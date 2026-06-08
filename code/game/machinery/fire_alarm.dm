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
	var/timing = 0.0
	var/lockdownbyai = 0
	anchored = TRUE
	unacidable = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 2
	active_power_usage = 6
	power_channel = ENVIRON
	var/last_process = 0
	panel_open = FALSE
	var/seclevel
	circuit = /obj/item/circuitboard/firealarm
	var/alarms_hidden = FALSE //If the alarms from this machine are visible on consoles

	var/datum/looping_sound/alarm/fire_alarm/soundloop
	var/datum/looping_sound/alarm/engineering_alarm/engalarm
	var/datum/looping_sound/alarm/sm_critical_alarm/critalarm
	var/datum/looping_sound/alarm/sm_causality_alarm/causality

	var/firewarn = FALSE
	var/engwarn = FALSE
	var/critwarn = FALSE
	var/causalitywarn = FALSE

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

	soundloop = new(list(src), FALSE)
	engalarm = new(list(src), FALSE)
	critalarm = new(list(src), FALSE)
	causality = new(list(src), FALSE)

/obj/machinery/firealarm/Destroy()
	reset()
	QDEL_NULL(soundloop)
	QDEL_NULL(engalarm)
	QDEL_NULL(critalarm)
	QDEL_NULL(causality)
	return ..()

/obj/machinery/firealarm/proc/offset_alarm()
	pixel_x = (dir & 3) ? 0 : (dir == 4 ? 26 : -26)
	pixel_y = (dir & 3) ? (dir == 1 ? -26 : 26) : 0

/obj/machinery/firealarm/update_icon()
	cut_overlays()

	if(panel_open)
		set_light(0)
		return

	if(stat & BROKEN)
		icon_state = "firex"
		set_light(0)
		return
	else if(stat & NOPOWER)
		icon_state = "firep"
		set_light(0)
		return

	var/fire_state

	. = list()
	icon_state = "fire"
	if(!detecting)
		fire_state = "fire1"
		set_light(l_range = 4, l_power = 0.9, l_color = "#ff0000")
	else
		fire_state = "fire0"
		switch(seclevel)
			if("green")	set_light(l_range = 2, l_power = 0.25, l_color = "#00ff00")
			if("yellow")	set_light(l_range = 2, l_power = 0.25, l_color = "#ffff00")
			if("violet")	set_light(l_range = 2, l_power = 0.25, l_color = "#9933ff")
			if("orange")	set_light(l_range = 2, l_power = 0.25, l_color = "#ff9900")
			if("blue")	set_light(l_range = 2, l_power = 0.25, l_color = "#1024A9")
			if("red")	set_light(l_range = 4, l_power = 0.9, l_color = "#ff0000")
			if("delta")	set_light(l_range = 4, l_power = 0.9, l_color = "#FF6633")

	. += mutable_appearance(icon, fire_state)
	. += emissive_appearance(icon, fire_state)

	if(seclevel)
		. += mutable_appearance(icon, "overlay_[seclevel]")
		. += emissive_appearance(icon, "overlay_[seclevel]")

	add_overlay(.)

/obj/machinery/firealarm/fire_act(datum/gas_mixture/air, temperature, volume)
	if(detecting)
		if(temperature > T0C + 200)
			alarm()			// added check of detector status here
	return

/obj/machinery/firealarm/attack_ai(mob/user as mob)
	return attack_hand(user)

/obj/machinery/firealarm/bullet_act()
	return alarm()

/obj/machinery/firealarm/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	if(prob(50 / severity))
		alarm(rand(30 / severity, 60 / severity))

/obj/machinery/firealarm/attackby(obj/item/W as obj, mob/user as mob)
	add_fingerprint(user)

	if(alarm_deconstruction_screwdriver(user, W))
		return
	if(alarm_deconstruction_wirecutters(user, W))
		return

	if(panel_open)
		if(istype(W, /obj/item/multitool))
			detecting = !(detecting)
			if(detecting)
				user.visible_message(span_notice("\The [user] has reconnected [src]'s detecting unit!"), span_notice("You have reconnected [src]'s detecting unit."))
			else
				user.visible_message(span_notice("\The [user] has disconnected [src]'s detecting unit!"), span_notice("You have disconnected [src]'s detecting unit."))
		return

	alarm()
	return

/obj/machinery/firealarm/process()//Note: this processing was mostly phased out due to other code, and only runs when needed
	if(stat & (NOPOWER|BROKEN))
		return

	if(timing)
		if(time > 0)
			time = time - ((world.timeofday - last_process) / 10)
		else
			alarm()
			time = 0
			timing = 0
			STOP_PROCESSING(SSobj, src)
	last_process = world.timeofday

	if(detecting && (locate(/obj/fire) in loc))
		alarm()

	return

/obj/machinery/firealarm/power_change()
	..()
	addtimer(CALLBACK(src, PROC_REF(process_power_change)), rand(0, 15), TIMER_DELETE_ME)

/obj/machinery/firealarm/proc/process_power_change()
	update_icon()
	if(!soundloop)
		return
	if(stat & (NOPOWER | BROKEN))
		soundloop.stop()
		engalarm.stop()
		critalarm.stop()
		causality.stop()
	else
		if(firewarn)
			soundloop.start()
		if(engwarn)
			engalarm.start()
		if(critwarn)
			critalarm.start()
		if(causalitywarn)
			causality.start()

/obj/machinery/firealarm/attack_hand(mob/user as mob)
	if(user.stat || stat & (NOPOWER | BROKEN))
		return

	add_fingerprint(user)
	var/area/A = get_area(src)
	if(A.fire)
		reset(user)
	else
		alarm(0, user)

/obj/machinery/firealarm/proc/reset(mob/user)
	if(!(working))
		return
	var/area/area = get_area(src)
	for(var/obj/machinery/firealarm/FA in area)
		GLOB.fire_alarm.clearAlarm(src.loc, FA)
		FA.soundloop.stop()
		FA.firewarn = FALSE
	update_icon()
	if(user)
		log_game("[user] reset a fire alarm at [COORD(src)]")

/obj/machinery/firealarm/proc/alarm(duration = 0, mob/user)
	if(!(working))
		return
	var/area/area = get_area(src)
	if(!firewarn && !alarms_hidden)
		GLOB.global_announcer.autosay("Tripped [area]", "Fire Alarm Monitor", DEPARTMENT_ENGINEERING)
	for(var/obj/machinery/firealarm/FA in area)
		GLOB.fire_alarm.triggerAlarm(loc, FA, duration, hidden = alarms_hidden)
		FA.soundloop.start()
		FA.firewarn = TRUE
	update_icon()
	if(user)
		log_game("[user] triggered a fire alarm at [COORD(src)]")

/obj/machinery/firealarm/proc/set_security_level(newlevel)
	if(seclevel != newlevel)
		seclevel = newlevel
		update_icon()

/*
FIRE ALARM CIRCUIT
Just a object used in constructing fire alarms

/obj/item/firealarm_electronics
	name = "fire alarm electronics"
	icon = 'icons/obj/doors/door_assembly.dmi'
	icon_state = "door_electronics"
	desc = "A circuit. It has a label on it, it says \"Can handle heat levels up to 40 degrees celsius!\""
	w_class = ITEMSIZE_SMALL
	matter = RECYCLE_CIRCUIT_MATERIALS
*/
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

/obj/machinery/partyalarm/attack_hand(mob/user as mob)
	if(user.stat || stat & (NOPOWER|BROKEN))
		return
	user.set_machine(src)
	tgui_interact(user)

/obj/machinery/partyalarm/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "PartyAlarm", "Party Button")
		ui.open()

/obj/machinery/partyalarm/tgui_data(mob/user)
	var/list/data = list()
	var/area/A = get_area(src)
	data["party_on"] = !!A?.party
	data["timing"] = !!timing
	data["time"] = time
	data["scrambled"] = !(ishuman(user) || isAI(user))
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

/obj/machinery/partyalarm/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(ui.user.stat || stat & (BROKEN|NOPOWER))
		return TRUE
	switch(action)
		if("reset")
			reset()
			return TRUE
		if("alarm")
			alarm()
			return TRUE
		if("time")
			timing = text2num(params["value"])
			return TRUE
		if("tp")
			var/tp = text2num(params["value"])
			time += tp
			time = min(max(round(time), 0), 120)
			return TRUE
