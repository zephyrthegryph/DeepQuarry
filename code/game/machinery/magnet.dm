// Magnetic attractor, creates variable magnetic fields and attraction.
// Can also be used to emit electron/proton beams to create a center of magnetism on another tile

// tl;dr: it's magnets lol
// This was created for firing ranges, but I suppose this could have other applications - Doohl

/obj/machinery/magnetic_module
	icon = 'icons/obj/objects.dmi'
	icon_state = "floor_magnet-f"
	name = "Electromagnetic Generator"
	desc = "A device that uses station power to create points of magnetic energy."
	plane = PLATING_PLANE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 50

	var/freq = 1449		// radio frequency
	var/electricity_level = 1 // intensity of the magnetic pull
	var/magnetic_field = 1 // the range of magnetic attraction
	var/code = 0 // frequency code, they should be different unless you have a group of magnets working together or something
	var/turf/center // the center of magnetic attraction
	on = 0

	// x, y modifiers to the center turf; (0, 0) is centered on the magnet, whereas (1, -1) is one tile right, one tile down
	var/center_x = 0
	var/center_y = 0
	var/max_dist = 20 // absolute value of center_x,y cannot exceed this integer

/// Pulls things toward its center every magnet_delay() while switched on.


/obj/machinery/magnetic_module/Initialize(mapload)
	. = ..()
	var/turf/T = loc
	hide(!T.is_plating())
	rel_set(src, nameof(center), T)

	if(SSradio)
		SSradio.add_object(src, freq, RADIO_MAGNETS)

// update the invisibility and icon
/obj/machinery/magnetic_module/hide(intact)
	invisibility = intact ? INVISIBILITY_ABSTRACT : INVISIBILITY_NONE
	changed(src)

// update the icon_state
/// The look (the draw sweep: from its template).
/obj/machinery/magnetic_module/draw(datum/look/look)
	..()
	look.state("floor_magnet[on ? "" : "0"][invisibility ? "-f" : ""]")

/obj/machinery/magnetic_module/receive_signal(datum/signal/signal)
	var/command = signal.data["command"]
	var/modifier = signal.data["modifier"]
	var/signal_code = signal.data["code"]
	if(command && (signal_code == code))

		Cmd(command, modifier)

/obj/machinery/magnetic_module/proc/Cmd(command, modifier)
	if(command)
		switch(command)
			if("set-electriclevel")
				if(modifier)	electricity_level = modifier
			if("set-magneticfield")
				if(modifier)	magnetic_field = modifier

			if("add-elec")
				electricity_level++
				if(electricity_level > 12)
					electricity_level = 12
			if("sub-elec")
				electricity_level--
				if(electricity_level <= 0)
					electricity_level = 1
			if("add-mag")
				magnetic_field++
				if(magnetic_field > 4)
					magnetic_field = 4
			if("sub-mag")
				magnetic_field--
				if(magnetic_field <= 0)
					magnetic_field = 1

			if("set-x")
				if(modifier)	center_x = modifier
			if("set-y")
				if(modifier)	center_y = modifier

			if("N") // NORTH
				center_y++
			if("S")	// SOUTH
				center_y--
			if("E") // EAST
				center_x++
			if("W") // WEST
				center_x--
			if("C") // CENTER
				center_x = 0
				center_y = 0
			if("R") // RANDOM
				center_x = rand(-max_dist, max_dist)
				center_y = rand(-max_dist, max_dist)

			if("set-code")
				if(modifier)	code = modifier
			if("toggle-power")
				set_on(!on)
	work_start(src)

/// Clamps its settings and reconciles its power draw and icon: after every command, and on
/// every power or break change.
// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/magnetic_module)
	every(PROC_REF(magnet_delay), then(PROC_REF(magnetic_process)), when = nameof(on))
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition), wakes_on = list(STAT_OPERABLE), unpowered = TRUE)

/obj/machinery/magnetic_module/proc/work_step(datum/act/timer/A)
	if(power_lost())
		set_on(0)

	// Sanity checks:
	if(electricity_level <= 0)
		electricity_level = 1
	if(magnetic_field <= 0)
		magnetic_field = 1

	// Limitations:
	if(abs(center_x) > max_dist)
		center_x = max_dist
	if(abs(center_y) > max_dist)
		center_y = max_dist
	if(magnetic_field > 4)
		magnetic_field = 4
	if(electricity_level > 12)
		electricity_level = 12

	// Update power usage:
	if(on)
		set_use_power(USE_POWER_ACTIVE)
		update_active_power_usage(electricity_level * 15)
	else
		set_use_power(USE_POWER_OFF)

	return PROCESS_KILL

/// The pull's period: stronger fields pull faster.
/obj/machinery/magnetic_module/proc/magnet_delay(datum/act/timer/A)
	return (13 - electricity_level) DECISECONDS

/obj/machinery/magnetic_module/proc/magnetic_process(datum/act/timer/A) // proc that actually does the pulling
	rel_set(src, nameof(center), locate(x+center_x, y+center_y, z))
	if(get_center())
		for(var/obj/M in orange(magnetic_field, get_center()))
			if(!M.anchored && !(M.flags & NOCONDUCT))
				step_towards(M, get_center())
		for(var/mob/living/silicon/S in orange(magnetic_field, get_center()))
			if(isAI(S)) continue
			step_towards(S, get_center())

	use_power(electricity_level * 5)

/obj/machinery/magnetic_controller
	name = "Magnetic Control Console"
	icon = 'icons/obj/airlock_machines.dmi' // uses an airlock machine icon, THINK GREEN HELP THE ENVIRONMENT - RECYCLING!
	icon_state = "airlock_control_standby"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 45
	var/frequency = AMAG_ELE_FREQ
	var/code = 0
	var/list/magnets
	var/title = "Magnetic Control Console"
	var/autolink = 0 // if set to 1, can't probe for other magnets!

	var/pathpos = 1 // position in the path
	var/path = "NULL" // text path of the magnet
	var/speed = 1 // lowest = 1, highest = 10
	var/list/rpath // real path of the magnet, used in iterator

	var/datum/radio_frequency/radio_connection

/// TRUE while the magnets are walked along the path.
/obj/machinery/magnetic_controller/var/path_moving = FALSE
TRACKED_BRIDGED(/obj/machinery/magnetic_controller, path_moving, CHANGE_MACHINE_SETTINGS)
/obj/machinery/magnetic_controller/var/path_stopped = FALSE
TRACKED(/obj/machinery/magnetic_controller, path_stopped)
/// Walks the magnets one path step every magnet_delay() while moving.
/obj/machinery/magnetic_controller/proc/reset_path_repeat(datum/act/A)
	set_path_stopped(FALSE)

/obj/machinery/magnetic_controller/Initialize(mapload)
	. = ..()

	if(autolink)
		for(var/obj/machinery/magnetic_module/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(M.freq == frequency && M.code == code)
				rel_add(src, nameof(magnets), M)

	if(SSradio)
		rel_set(src, nameof(radio_connection), SSradio.add_object(src, frequency, RADIO_MAGNETS))

	if(path) // check for default path
		filter_path() // renders rpath

/// Autolinks once at Initialize (its one frame) if Initialize found no magnets yet.
/obj/machinery/magnetic_controller/proc/work_step(datum/act/timer/A)
	if(length(magnets) == 0 && autolink)
		for(var/obj/machinery/magnetic_module/M in REGISTRY_MEMBERS(REGISTRY_MACHINES))
			if(M.freq == frequency && M.code == code)
				rel_add(src, nameof(magnets), M)
	return PROCESS_KILL

// structured TGUI MagneticConsole (see
// code/modules/admin/magnetic_console_panel.dm).
/obj/machinery/magnetic_controller/proc/interaction_open(datum/act/op/A)
	var/mob/user = A.actor
	if(!operable())
		return TRUE
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

/// Sends a radio command (`op`) to the magnets on this controller's frequency.
/obj/machinery/magnetic_controller/proc/magnet_radio_op(mob/user, op)
	if(!operable())
		return
	// Prepare signal beforehand, because this is a radio operation
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO // radio transmission
	rel_set(signal, nameof(signal.source), src)
	signal.frequency = frequency
	signal.data["code"] = code

	// Apply any necessary commands
	switch(op)
		if("togglepower")
			signal.data["command"] = "toggle-power"

		if("minuselec")
			signal.data["command"] = "sub-elec"
		if("pluselec")
			signal.data["command"] = "add-elec"

		if("minusmag")
			signal.data["command"] = "sub-mag"
		if("plusmag")
			signal.data["command"] = "add-mag"

	// Broadcast the signal
	radio_connection().post_signal(src, signal, radio_filter = RADIO_MAGNETS)
	updateUsrDialog(user)

/// A local controller operation (`op`): speed, path and movement.
/obj/machinery/magnetic_controller/proc/magnet_operation(mob/user, op)
	if(!operable())
		return
	switch(op)
		if("plusspeed")
			speed ++
			if(speed > 10)
				speed = 10
		if("minusspeed")
			speed --
			if(speed <= 0)
				speed = 1
		if("setpath")
			open_request(src, /datum/prompt/text, PROC_REF(magnet_path_entered), answerer = user, question = "Please define a new path!", default = path, max_len = MAX_MESSAGE_LEN, ask_flags = ASK_CAPABLE, timeout = 0)

		if("togglemoving")
			set_path_moving(!path_moving)

	updateUsrDialog(user)

/obj/machinery/magnetic_controller/proc/magnet_path_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/newpath = A.answer.value
	updateUsrDialog(user)
	if(newpath && newpath != "")
		set_path_moving(FALSE) // stop moving
		path = newpath
		pathpos = 1 // reset position
		filter_path() // renders rpath

/// The wait between path steps, by `speed`.
/obj/machinery/magnetic_controller/proc/magnet_delay(datum/act/timer/A)
	return (speed == 10 ? 1 : 12 - speed) DECISECONDS

/// One step of the magnet path: signal the next move.
/obj/machinery/magnetic_controller/proc/magnet_move_step(datum/act/timer/A)
	if(length(rpath) < 1 || (!operable()))
		set_path_stopped(TRUE)
		return

	if(pathpos > length(rpath)) // if the position is greater than the length, we just loop through the list!
		pathpos = 1

	var/nextmove = uppertext(LAZYACCESS(rpath, pathpos)) // makes it un-case-sensitive

	if(!(nextmove in list("N","S","E","W","C","R")))
		// N, S, E, W are directional
		// C is center
		// R is random (in magnetic field's bounds)
		set_path_stopped(TRUE)
		return // stop if the character located is invalid

	// Prepare the radio signal
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO // radio transmission
	rel_set(signal, nameof(signal.source), src)
	signal.frequency = frequency
	signal.data["code"] = code
	signal.data["command"] = nextmove

	pathpos++ // increase iterator

	// Broadcast the signal
	radio_connection().post_signal(src, signal, radio_filter = RADIO_MAGNETS)

/obj/machinery/magnetic_controller/proc/filter_path()
	// Generates the rpath variable using the path string, think of this as "string2list"
	// Doesn't use params2list() because of the akward way it stacks entities
	rpath = list() //  clear rpath
	var/maximum_character = min(50, length(path)) // chooses the maximum length of the iterator. 50 max length

	for(var/i=1, i<=maximum_character, i++) // iterates through all characters in path

		var/nextchar = copytext(path, i, i+1) // find next character

		if(!(nextchar in list(";", "&", "*", " "))) // if char is a separator, ignore
			LAZYADD(rpath, copytext(path, i, i+1)) // else, add to list

		// there doesn't HAVE to be separators but it makes paths syntatically visible

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/magnetic_module/step_start_condition()
	return TRUE // its power draw

/// center (a relation view: it reads null once the target is deleted).
/obj/machinery/magnetic_module/proc/get_center() as /turf
	return center

/// radio connection (a relation view: it reads null once the target is deleted).
/obj/machinery/magnetic_controller/proc/radio_connection() as /datum/radio_frequency
	return radio_connection
