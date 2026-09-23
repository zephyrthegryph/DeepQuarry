#define OP_COMPUTER_COOLDOWN 60

/obj/machinery/computer/operating
	name = "patient monitoring console"
	desc = "Used to monitor the vitals of a patient."
	density = TRUE
	anchored = TRUE
	icon_keyboard = "med_key"
	icon_screen = "crew"
	circuit = /obj/item/circuitboard/operating
	var/obj/machinery/optable/table = null
	var/mob/living/carbon/human/victim = null
	var/verbose = 1 //general speaker toggle
	var/patientName = null
	var/oxyAlarm = 30 //oxy damage at which the computer will beep
	var/choice = 0 //just for going into and out of the options menu
	var/healthAnnounce = 1 //healther announcer toggle
	var/crit = 1 //crit beeping toggle
	var/nextTick = OP_COMPUTER_COOLDOWN
	var/healthAlarm = 50
	var/oxy = 1 //oxygen beeping toggle

/obj/machinery/computer/operating/Initialize(mapload)
	. = ..()
	for(var/direction in list(NORTH,EAST,SOUTH,WEST))
		table = locate(/obj/machinery/optable, get_step(src, direction))
		if(table)
			table.computer = src
			break

/obj/machinery/computer/operating/Destroy()
	if(table)
		table.computer = null
		table = null
	if(victim)
		victim = null
	return ..()

/obj/machinery/computer/operating/attack_ai(mob/user)
	add_fingerprint(user)
	if(stat & (BROKEN|NOPOWER))
		return
	tgui_interact(user)


/obj/machinery/computer/operating/attack_hand(mob/user)
	add_fingerprint(user)
	if(stat & (BROKEN|NOPOWER))
		return
	tgui_interact(user)

/obj/machinery/computer/operating/tgui_interact(mob/user, datum/tgui/ui = null)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "OperatingComputer", "Patient Monitor")
		ui.open()

/obj/machinery/computer/operating/tgui_data(mob/user)
	var/data[0]
	var/mob/living/carbon/human/occupant
	if(table)
		occupant = table.victim
	data["hasOccupant"] = occupant ? 1 : 0
	var/occupantData[0]

	if(occupant)
		occupantData["name"] = occupant.name
		occupantData["stat"] = occupant.stat
		// UI keys kept for the tgui interface: health is vitality as a percentage.
		occupantData["health"] = round(occupant.vitality() * 100)
		occupantData["maxHealth"] = 100
		occupantData["minHealth"] = 0
		occupantData["bruteLoss"] = occupant.injury_load(INJURY_CATEGORY_PHYSICAL)
		occupantData["oxyLoss"] = occupant.injury_load(INJURY_CATEGORY_ASPHYXIA)
		occupantData["toxLoss"] = occupant.injury_load(INJURY_CATEGORY_TOXIC)
		occupantData["fireLoss"] = occupant.injury_load(INJURY_CATEGORY_THERMAL)
		occupantData["paralysis"] = occupant.paralysis
		occupantData["hasBlood"] = 0
		occupantData["bodyTemperature"] = occupant.bodytemperature
		occupantData["maxTemp"] = 1000 // If you get a burning vox armalis into the sleeper, congratulations
		// Because we can put simple_animals in here, we need to do something tricky to get things working nice
		occupantData["temperatureSuitability"] = 0 // 0 is the baseline
		if(ishuman(occupant) && occupant.species)
			// I wanna do something where the bar gets bluer as the temperature gets lower
			// For now, I'll just use the standard format for the temperature status
			var/datum/species/sp = occupant.species
			if(occupant.bodytemperature < sp.cold_level_3)
				occupantData["temperatureSuitability"] = -3
			else if(occupant.bodytemperature < sp.cold_level_2)
				occupantData["temperatureSuitability"] = -2
			else if(occupant.bodytemperature < sp.cold_level_1)
				occupantData["temperatureSuitability"] = -1
			else if(occupant.bodytemperature > sp.heat_level_3)
				occupantData["temperatureSuitability"] = 3
			else if(occupant.bodytemperature > sp.heat_level_2)
				occupantData["temperatureSuitability"] = 2
			else if(occupant.bodytemperature > sp.heat_level_1)
				occupantData["temperatureSuitability"] = 1
		else if(isanimal(occupant))
			var/mob/living/simple_mob/silly = occupant
			if(silly.bodytemperature < silly.minbodytemp)
				occupantData["temperatureSuitability"] = -3
			else if(silly.bodytemperature > silly.maxbodytemp)
				occupantData["temperatureSuitability"] = 3
		// Blast you, imperial measurement system
		occupantData["btCelsius"] = occupant.bodytemperature - T0C
		occupantData["btFaren"] = ((occupant.bodytemperature - T0C) * (9.0/5.0))+ 32

		if(ishuman(occupant) && !(NO_BLOOD in occupant.species.flags) && occupant.vessel)
			occupantData["pulse"] = occupant.get_pulse(GETPULSE_TOOL)
			occupantData["hasBlood"] = 1
			var/blood_volume = round(occupant.vessel.get_reagent_amount(REAGENT_ID_BLOOD))
			occupantData["bloodLevel"] = blood_volume
			occupantData["bloodMax"] = occupant.species.blood_volume
			occupantData["bloodPercent"] = occupant.species.blood_volume ? round(100*(blood_volume/occupant.species.blood_volume), 0.01) : 0 //copy pasta ends here, some species have no blood volume

			occupantData["bloodType"] = occupant.dna.b_type
			occupantData["surgery"] = build_surgery_list(user)

	data["occupant"] = occupantData
	data["verbose"]=verbose
	data["oxyAlarm"]=oxyAlarm
	data["choice"]=choice
	data["health"]=healthAnnounce
	data["crit"]=crit
	data["healthAlarm"]=healthAlarm
	data["oxy"]=oxy

	return data

/obj/machinery/computer/operating/tgui_act(action, params, datum/tgui/ui)
	if(..())
		return TRUE
	if((ui.user.contents.Find(src) || (in_range(src, ui.user) && istype(src.loc, /turf))) || (istype(ui.user, /mob/living/silicon)))
		ui.user.set_machine(src)

	. = TRUE
	switch(action)
		if("verboseOn")
			verbose = TRUE
		if("verboseOff")
			verbose = FALSE
		if("healthOn")
			healthAnnounce = TRUE
		if("healthOff")
			healthAnnounce = FALSE
		if("critOn")
			crit = TRUE
		if("critOff")
			crit = FALSE
		if("oxyOn")
			oxy = TRUE
		if("oxyOff")
			oxy = FALSE
		if("oxy_adj")
			oxyAlarm = clamp(text2num(params["new"]), -100, 100)
		if("choiceOn")
			choice = TRUE
		if("choiceOff")
			choice = FALSE
		if("health_adj")
			healthAlarm = clamp(text2num(params["new"]), -100, 100)
		else
			return FALSE

/obj/machinery/computer/operating/process()
	if(!table || !table.check_victim())
		victim = null
		patientName = null
		return PROCESS_KILL
	if(table && table.victim)
		if(verbose)
			if(patientName!=table.victim.name)
				patientName=table.victim.name
				atom_say("New patient detected, loading stats")
				victim = table.victim
				atom_say("[victim.real_name], [victim.dna.b_type] blood, [victim.stat ? "Non-Responsive" : "Awake"]")
				SStgui.update_uis(src)
			if(nextTick < world.time)
				nextTick=world.time + OP_COMPUTER_COOLDOWN
				if(crit && victim.is_critical())
					playsound(src.loc, 'sound/machines/defib_success.ogg', 50, 0)
				if(oxy && victim.injury_load(INJURY_CATEGORY_ASPHYXIA) > oxyAlarm)
					playsound(src.loc, 'sound/machines/defib_safetyOff.ogg', 50, 0)
				if(healthAnnounce && victim.vitality() * 100 <= healthAlarm)
					atom_say("[round(victim.vitality() * 100)]% vitality.")

// Surgery Helpers
/obj/machinery/computer/operating/proc/build_surgery_list(mob/user)
	if(!istype(victim))
		return null

	. = list()

	for(var/limb in victim.organs_by_name)
		var/obj/item/organ/external/E = victim.organs_by_name[limb]
		if(E && E.open)
			. += list(list("name" = E.name, "currentStage" = find_stage(E), "nextSteps" = find_next_steps(user, limb)))

/// The surgical site's state, from the limb's incision.
/obj/machinery/computer/operating/proc/find_stage(obj/item/organ/external/E)
	return E.surgery_state_text()

/// What can be done next at `zone`, with the proper tools for each step.
/obj/machinery/computer/operating/proc/find_next_steps(mob/user, zone)
	. = list()
	for(var/datum/surgical_step/S as anything in next_surgical_steps(user, victim, zone))
		var/list/allowed_tools_by_name = list()
		for(var/tool in S.allowed_tools)
			// Exempt improvised tools.
			if(S.allowed_tools[tool] < 100)
				continue
			var/obj/tool_path = tool
			allowed_tools_by_name += capitalize(initial(tool_path.name))
		. += "[S.name]: [english_list(allowed_tools_by_name)]"

#undef OP_COMPUTER_COOLDOWN
