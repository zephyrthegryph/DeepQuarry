// LINDA atmospherics rewrite (commit 6fdac16ef1). gas_mixture var accesses (e.g. mix.total_moles) converted to proc calls (mix.total_moles()) for the LINDA engine API. Bulk rewrite by tools/verdigris/linda_rewrite_chomp_atmos.py.
// Bracketed at file-header rather than per-hunk because the
// edits are mechanical and span the whole file; the commit SHA
// is the source of truth for per-line diff context.

/// 72 kg of tissue at about 3470 J/(kg K).

/obj/machinery/atmospherics/unary/cryo_cell
	name = "cryo cell"
	desc = "Used to cool people down for medical reasons. Totally."
	icon = 'icons/obj/cryogenics.dmi' // map only
	icon_state = "pod_preview"
	density = TRUE
	anchored = TRUE
	flags = REMOTEVIEW_ON_ENTER
	layer = UNDER_JUNK_LAYER
	interact_offline = 1

	var/on = 0
	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 200
	buckle_lying = FALSE
	buckle_dir = SOUTH
	clicksound = 'sound/machines/buttonbeep.ogg'
	clickvol = 30

	var/temperature_archived
	var/mob/living/carbon/occupant = null
	var/obj/item/reagent_containers/glass/beaker = null

	var/image/fluid

/obj/machinery/atmospherics/unary/cryo_cell/Initialize(mapload)
	. = ..()
	icon = 'icons/obj/cryogenics_split.dmi'
	icon_state = "base"
	initialize_directions = dir
	var/image/tank = image(icon,"tank")
	tank.alpha = 200
	tank.pixel_y = 18
	tank.plane = MOB_PLANE
	tank.layer = MOB_LAYER+0.2 //Above fluid
	fluid = image(icon, "tube_filler")
	fluid.pixel_y = 18
	fluid.alpha = 200
	fluid.plane = MOB_PLANE
	fluid.layer = MOB_LAYER+0.1 //Below glass, above mob
	add_overlay(tank)
	update_icon()

/obj/machinery/atmospherics/unary/cryo_cell/Destroy()
	var/turf/T = src.loc
	T.contents += contents
	if(beaker)
		beaker.forceMove(get_step(loc, SOUTH)) //Beaker is carefully ejected from the wreckage of the cryotube
		beaker = null
	. = ..()

/obj/machinery/atmospherics/unary/cryo_cell/process()
	..()
	if(!on)
		return PROCESS_KILL
	if(!node)
		return

	if(air_contents)
		temperature_archived = air_contents.return_temperature()

	if(occupant)
		if(occupant.stat != 2)
			process_occupant()

	if(air_contents)
		expel_gas()

	if(air_contents && abs(temperature_archived-air_contents.return_temperature()) > 1)
		network?.mark_dirty()

	return 1

/obj/machinery/atmospherics/unary/cryo_cell/relaymove(mob/user as mob)
	// note that relaymove will also be called for mobs outside the cell with UI open
	if(occupant == user && !user.stat)
		go_out()

/obj/machinery/atmospherics/unary/cryo_cell/attack_ghost(mob/user)
	tgui_interact(user)

/obj/machinery/atmospherics/unary/cryo_cell/attack_hand(mob/user)
	if(user == occupant)
		return

	if(panel_open)
		to_chat(user, span_boldnotice("Close the maintenance panel first."))
		return

	tgui_interact(user)

/obj/machinery/atmospherics/unary/cryo_cell/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Cryo", "Cryo Cell") // 520, 470
		ui.open()

/obj/machinery/atmospherics/unary/cryo_cell/tgui_data(mob/user)
	// this is the data which will be sent to the ui
	var/data[0]
	data["isOperating"] = on
	data["hasOccupant"] = occupant ? TRUE : FALSE

	var/occupantData[0]
	if(occupant)
		occupantData["name"] = occupant.name
		occupantData["stat"] = occupant.stat
		occupantData["vitality"] = round(occupant.vitality() * 100)
		occupantData["critical"] = occupant.is_critical()
		var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/automation)
		occupantData["diagnosis"] = D.report_data()
		qdel(D)
		occupantData["bodyTemperature"] = occupant.bodytemperature
	data["occupant"] = occupantData;

	var/air_temperature = air_contents.return_temperature()
	data["cellTemperature"] = round(air_temperature)
	data["cellTemperatureStatus"] = "good"
	if(air_temperature > T0C) // if greater than 273.15 kelvin (0 celcius)
		data["cellTemperatureStatus"] = "bad"
	else if(air_temperature > 225)
		data["cellTemperatureStatus"] = "average"

	data["isBeakerLoaded"] = beaker ? TRUE : FALSE
	data["beakerLabel"] = null
	data["beakerVolume"] = 0
	if(beaker)
		data["beakerLabel"] = beaker.label_text ? beaker.label_text : null
		if(beaker.reagents && beaker.reagents.reagent_list.len)
			for(var/datum/reagent/R in beaker.reagents.reagent_list)
				data["beakerVolume"] += R.volume

	return data

/obj/machinery/atmospherics/unary/cryo_cell/tgui_act(action, params, datum/tgui/ui)
	if(..() || ui.user == occupant)
		return TRUE

	. = TRUE
	switch(action)
		if("switchOn")
			on = 1
			START_MACHINE_PROCESSING(src)
			update_icon()
		if("switchOff")
			on = 0
			update_icon()
		if("ejectBeaker")
			if(beaker)
				beaker.forceMove(get_step(src.loc, SOUTH))
				beaker = null
				update_icon()
		if("ejectOccupant")
			if(!occupant || isslime(ui.user) || ispAI(ui.user))
				return 0 // don't update UIs attached to this object
			go_out()
		else
			return FALSE

	add_fingerprint(ui.user)

/obj/machinery/atmospherics/unary/cryo_cell/attackby(obj/item/G as obj, mob/user as mob)
	if(istype(G, /obj/item/reagent_containers/glass))
		if(beaker)
			to_chat(user, span_warning("A beaker is already loaded into the machine."))
			return

		beaker =  G
		user.drop_item()
		G.forceMove(src)
		user.visible_message("[user] adds \a [G] to \the [src]!", "You add \a [G] to \the [src]!")
		SStgui.update_uis(src)
		update_icon()
	else if(istype(G, /obj/item/grab))
		var/obj/item/grab/grab = G
		if(!ismob(grab.affecting))
			return
		if(occupant)
			to_chat(user,span_warning("\The [src] is already occupied by [occupant]."))
		if(grab.affecting.has_buckled_mobs())
			to_chat(user, span_warning("\The [grab.affecting] has other entities attached to it. Remove them first."))
			return
		var/mob/M = grab.affecting
		qdel(grab)
		put_mob(M)

	return

/obj/machinery/atmospherics/unary/cryo_cell/MouseDrop_T(mob/target, mob/user) //Allows borgs to put people into cryo without external assistance
	if(user.stat || user.lying || !Adjacent(user) || !target.Adjacent(user)|| !ishuman(target))
		return
	put_mob(target)

/obj/machinery/atmospherics/unary/cryo_cell/update_icon()
	cut_overlay(fluid)
	fluid.color = null
	if(on)
		if(beaker)
			fluid.color = beaker.reagents.get_color()
		add_overlay(fluid)

/obj/machinery/atmospherics/unary/cryo_cell/proc/process_occupant()
	if(air_contents.total_moles() < 10)
		return
	if(occupant)
		if(occupant.stat >= DEAD)
			return
		// The occupant and the cell's gas settle to a shared temperature; the
		// heat the body loses is what the gas gains.
		var/air_heat_capacity = air_contents.heat_capacity()
		var/equilibrium_temperature = (HUMAN_HEAT_CAPACITY * occupant.bodytemperature + air_heat_capacity * air_contents.return_temperature()) / (HUMAN_HEAT_CAPACITY + air_heat_capacity)
		occupant.bodytemperature = equilibrium_temperature
		air_contents.set_temperature(equilibrium_temperature)
		occupant.set_stat(UNCONSCIOUS)
		occupant.dir = SOUTH
		if(occupant.bodytemperature < T0C)
			occupant.Sleeping(max(5, (1/occupant.bodytemperature)*2000))
			occupant.Paralyse(max(5, (1/occupant.bodytemperature)*3000))
			occupant.mend(TREAT_OXYGENATION, 1)
			//severe damage should heal waaay slower without proper chemicals
			if(occupant.bodytemperature < 225)
				var/toxic_load = occupant.injury_load(INJURY_CATEGORY_TOXIC)
				if(toxic_load)
					occupant.mend(TREAT_ANTITOXIN, min(1, 20 / toxic_load))
				if(occupant.radiation || occupant.accumulated_rads)
					occupant.radiation -= 25
					occupant.accumulated_rads -= 25
				var/physical_load = occupant.injury_load(INJURY_CATEGORY_PHYSICAL)
				if(physical_load)
					occupant.mend(TREAT_TISSUE_REPAIR, min(1, 20 / physical_load))
				var/thermal_load = occupant.injury_load(INJURY_CATEGORY_THERMAL)
				if(thermal_load)
					occupant.mend(TREAT_BURN_CARE, min(1, 20 / thermal_load))
		var/has_cryo = occupant.reagents.get_reagent_amount(REAGENT_ID_CRYOXADONE) >= 1
		var/has_clonexa = occupant.reagents.get_reagent_amount(REAGENT_ID_CLONEXADONE) >= 1
		var/has_cryo_medicine = has_cryo || has_clonexa
		if(beaker && !has_cryo_medicine)
			beaker.reagents.trans_to_mob(occupant, 1, CHEM_BLOOD, 10, can_dialysis = FALSE)

/obj/machinery/atmospherics/unary/cryo_cell/proc/expel_gas()
	if(air_contents.total_moles() < 1)
		return
//	var/datum/gas_mixture/expel_gas = new
//	var/remove_amount = air_contents.total_moles()/50
//	expel_gas = air_contents.remove(remove_amount)

	// Just have the gas disappear to nowhere.
	//expel_gas.temperature = T20C // Lets expel hot gas and see if that helps people not die as they are removed
	//loc.assume_air(expel_gas)

/obj/machinery/atmospherics/unary/cryo_cell/proc/go_out()
	if(!(occupant))
		return
	vis_contents -= occupant
	occupant.pixel_x = occupant.default_pixel_x
	occupant.pixel_y = occupant.default_pixel_y
	occupant.forceMove(get_step(src.loc, SOUTH))	//this doesn't account for walls or anything, but i don't forsee that being a problem.
	if(occupant.bodytemperature < 261 && occupant.bodytemperature >= 70) //Patch by Aranclanos to stop people from taking burn damage after being ejected
		occupant.bodytemperature = 261									  // Changed to 70 from 140 by Zuhayr due to reoccurance of bug.
	unbuckle_mob(occupant, force = TRUE)
	occupant.cozyloop.stop() // Cozy Music
	occupant = null
	update_use_power(USE_POWER_IDLE)
	SStgui.update_uis(src)
	return

/obj/machinery/atmospherics/unary/cryo_cell/proc/put_mob(mob/living/carbon/M as mob)
	if(stat & (NOPOWER|BROKEN))
		to_chat(usr, span_warning("The cryo cell is not functioning."))
		return
	if(!istype(M))
		to_chat(usr, span_danger("The cryo cell cannot handle such a lifeform!"))
		return
	if(occupant)
		to_chat(usr, span_danger("The cryo cell is already occupied!"))
		return
	if(M.abiotic())
		to_chat(usr, span_warning("Subject may not have abiotic items on."))
		return
	if(!node)
		to_chat(usr, span_warning("The cell is not correctly connected to its pipe network!"))
		return
	M.stop_pulling()
	M.forceMove(src)
	M.extinguish_mob()
	if(M.stat != DEAD && (M.is_critical() || M.sleeping))
		to_chat(M, span_boldnotice("You feel a cold liquid surround you. Your skin starts to freeze up."))
	occupant = M
	if(on)
		START_MACHINE_PROCESSING(src)
	occupant.cozyloop.start() // Cozy Music
	buckle_mob(occupant, forced = TRUE, check_loc = FALSE)
	vis_contents |= occupant
	occupant.pixel_y += 19
	update_use_power(USE_POWER_ACTIVE)
//	M.metabslow = 1
	add_fingerprint(usr)
	update_icon()
	SStgui.update_uis(src)
	return 1

/obj/machinery/atmospherics/unary/cryo_cell/verb/move_eject()
	set name = "Eject occupant"
	set category = "Object"
	set src in oview(1)
	if(usr == occupant)//If the user is inside the tube...
		if(usr.stat == 2)//and he's not dead....
			return
		to_chat(usr, span_notice("Release sequence activated. This will take two minutes."))
		sleep(1200)
		if(!src || !usr || !occupant || (occupant != usr)) //Check if someone's released/replaced/bombed him already
			return
		go_out()//and release him from the eternal prison.
	else
		if(usr.stat != 0)
			return
		go_out()
	add_fingerprint(usr)
	return

/obj/machinery/atmospherics/unary/cryo_cell/verb/move_inside()
	set name = "Move Inside"
	set category = "Object"
	set src in oview(1)
	if(isliving(usr))
		var/mob/living/L = usr
		if(L.has_buckled_mobs())
			to_chat(L, span_warning("You have other entities attached to yourself. Remove them first."))
			return
		if(L.stat != CONSCIOUS)
			return
		put_mob(L)

/atom/proc/return_air_for_internal_lifeform(mob/living/lifeform)
	return return_air()

/obj/machinery/atmospherics/unary/cryo_cell/return_air_for_internal_lifeform()
	//assume that the cryo cell has some kind of breath mask or something that
	//draws from the cryo tube's environment, instead of the cold internal air.
	if(src.loc)
		return loc.return_air()
	else
		return null

/datum/data/function/proc/reset()
	return

/datum/data/function/proc/r_input(href, href_list, mob/user)
	return

/datum/data/function/proc/display()
	return

