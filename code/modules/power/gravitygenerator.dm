// It.. uses a lot of power.  Everything under power is engineering stuff, at least.

/obj/machinery/computer/gravity_control_computer
	name = "gravity generator control"
	desc = "A computer to control a local gravity generator.  Qualified personnel only."
	icon_state = "airtunnel0e"
	anchored = TRUE
	density = TRUE
	var/obj/machinery/gravity_generator = null


/obj/machinery/gravity_generator
	name = "gravitational generator"
	desc = "A device which produces a gravaton field when set up."
	icon = 'icons/obj/singularity.dmi'
	icon_state = "TheSingGen"
	anchored = TRUE
	density = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 200
	active_power_usage = 1000
	var/on = 1
	var/list/localareas = list()
	var/effectiverange = 25

	// Borrows code from cloning computer
/obj/machinery/computer/gravity_control_computer/Initialize(mapload)
	. = ..()
	updatemodules()

/obj/machinery/gravity_generator/Initialize(mapload)
	. = ..()
	locatelocalareas()

/obj/machinery/computer/gravity_control_computer/proc/updatemodules()
	src.gravity_generator = findgenerator()

/obj/machinery/gravity_generator/proc/locatelocalareas()
	for(var/area/A in range(src,effectiverange))
		if(A.name == "Space")
			continue // No (de)gravitizing space.
		if(!(A in localareas))
			localareas += A

/obj/machinery/computer/gravity_control_computer/proc/findgenerator()
	var/obj/machinery/gravity_generator/foundgenerator = null
	for(dir in list(NORTH,EAST,SOUTH,WEST))
		//to_world("SEARCHING IN [dir]")
		foundgenerator = locate(/obj/machinery/gravity_generator/, get_step(src, dir))
		if (!isnull(foundgenerator))
			//to_world("FOUND")
			break
	return foundgenerator

/obj/machinery/computer/gravity_control_computer/attack_ai(mob/user as mob)
	return attack_hand(user)

// DQEdit Start — TGUI migration. attack_hand opens GravityGeneratorControl;
// Topic toggle moves to tgui_act.
/obj/machinery/computer/gravity_control_computer/attack_hand(mob/user as mob)
	user.set_machine(src)
	add_fingerprint(user)
	if(stat & (BROKEN|NOPOWER))
		return
	updatemodules()
	tgui_interact(user)

/obj/machinery/computer/gravity_control_computer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "GravityGeneratorControl", "Gravity Generator Control")
		ui.open()

/obj/machinery/computer/gravity_control_computer/tgui_data(mob/user)
	var/list/data = list()
	data["has_generator"] = !!gravity_generator
	data["generator_on"] = gravity_generator ? !!gravity_generator:on : FALSE
	var/list/areas = list()
	if(gravity_generator)
		for(var/area/A in gravity_generator:localareas)
			areas += list(list(
				"name" = "[A]",
				"has_gravity" = !!A.has_gravity,
				"fed_by_us" = (A.has_gravity && gravity_generator:on),
			))
	data["areas"] = areas
	return data

/obj/machinery/computer/gravity_control_computer/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	switch(action)
		if("toggle")
			if(!gravity_generator)
				return TRUE
			if(gravity_generator:on)
				gravity_generator:on = 0
				for(var/area/A in gravity_generator:localareas)
					var/obj/machinery/gravity_generator/G
					for(G in GLOB.machines)
						if((A in G.localareas) && (G.on))
							break
					if(!G)
						A.gravitychange(0)
			else
				for(var/area/A in gravity_generator:localareas)
					gravity_generator:on = 1
					A.gravitychange(1)
			return TRUE
// DQEdit End
