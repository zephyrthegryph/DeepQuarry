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
	var/spo2Alarm = 90 //SpO2 (%) below which the computer will beep
	var/choice = 0 //just for going into and out of the options menu
	var/healthAnnounce = 1 //healther announcer toggle
	var/crit = 1 //crit beeping toggle
	var/nextTick = OP_COMPUTER_COOLDOWN
	var/healthAlarm = 50
	var/spo2 = 1 //SpO2 beeping toggle

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
		occupantData["vitality"] = round(occupant.vitality() * 100)
		occupantData["paralysis"] = occupant.paralysis
		var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/operating_computer)
		occupantData["diagnosis"] = D.report_data()
		qdel(D)
		if(ishuman(occupant) && occupant.dna)
			occupantData["bloodType"] = occupant.dna.b_type
			occupantData["surgery"] = build_surgery_list(user)

	data["occupant"] = occupantData
	data["verbose"]=verbose
	data["spo2Alarm"]=spo2Alarm
	data["choice"]=choice
	data["health"]=healthAnnounce
	data["crit"]=crit
	data["healthAlarm"]=healthAlarm
	data["spo2"]=spo2

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
		if("spo2On")
			spo2 = TRUE
		if("spo2Off")
			spo2 = FALSE
		if("spo2_adj")
			spo2Alarm = clamp(text2num(params["new"]), 0, 100)
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
				var/saturation = victim.body?.oxygenation()
				if(spo2 && !isnull(saturation) && saturation < spo2Alarm)
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

/**
 * This proc is actually hell. I hate the surgery system Polaris uses.
 * Basically, surgery is completely stateless, and what "stage" we're on is just dependent
 * on the current state of 5 separate variables that determine what stages we can perform
 * next.
 *
 * So, here's a little guide to understand this proc:
 * Surgery is broken down into 5 different variables:
 *		`open`,
 *		`stage`,
 *		`cavity`,
 *		`burn_stage`,
 *		and `brute_stage`.
 * Naturally, the values assigned to these don't use defines or names or anything, they're just magic numbers.
 * So, we have to figure out ourselves what we should call each value.
 * Open can be 4 values, and represents the "openness" of the surgery site.
 *		1 = Cut Open.
 *		2 = Retracted.
 *		2.5 = Bones cut.
 *		3 = Bones spread.
 * Stage can be 3 values, and represents the progress in fixing broken bones
 *		0 = Closed, can be either "we're done" or "we haven't started" FFS.
 *		1 = Bones glued.
 *		2 = Bones set.
 * Cavity is just representing the cavity implant surgeries, and can be 2 values.
 *		0 = Cavity Closed
 *		1 = Cavity Open
 * burn_stage and brute_stage are literally only used for repairing brute/burn damage to limbs
 * I have no idea why you would ever perform these surgeries, given that Bicaradine and Kelotane exist.
 * So I'm not even going to bother trying to represent them here. Fuck it.
 */
/obj/machinery/computer/operating/proc/find_stage(obj/item/organ/external/E)
	. = "None."
	switch(E.open)
		if(1)
			. = "Incision made."
		if(2)
			. = "Surgical site opened."
			switch(E.stage)
				// if(0) // Nothing.
				if(1)
					. = "Surgical site opened; Bones glued."
				if(2)
					. = "Surgical site opened; Bones set."
			switch(E.cavity)
				if(1)
					. = "Surgical site opened; Cavity open."
		if(2.5) // WHY IS THIS A FLOAT. WHY?
			. = "Bones cut."
			switch(E.stage)
				// if(0) // Nothing.
				if(1)
					. = "Bones cut; Bones glued."
				if(2)
					. = "Bones cut; Bones set."
		if(3)
			. = "Bones retracted."
			switch(E.stage)
				// if(0) // Nothing.
				if(1)
					. = "Bones retracted; Bones glued."
				if(2)
					. = "Bones retracted; Bones reset."
			switch(E.cavity)
				if(1)
					. = "Bones retracted; Cavity open."

/**
 * This converts a typepath into a pretty name.
 * As best as it can, anyways.
 */
/proc/pretty_type(datum/A)
	var/typeStr = "[A.type]"
	. = copytext(typeStr, findlasttext(typeStr, "/") + 1, length(typeStr) + 1)
	. = capitalize(replacetext(., "_", " "))

/proc/get_surgery_steps_without_basetypes()
	var/static/list/good_surgeries = list()
	if(LAZYLEN(good_surgeries))
		return good_surgeries
	var/static/list/banned_surgery_steps = list(
			/datum/surgery_step,
			/datum/surgery_step/generic,
			/datum/surgery_step/open_encased,
			/datum/surgery_step/repairflesh,
			/datum/surgery_step/face,
			/datum/surgery_step/cavity,
			/datum/surgery_step/limb,
			/datum/surgery_step/brainstem,
			/datum/surgery_step/generic/ripper,
		)
	good_surgeries = GLOB.surgery_steps
	for(var/datum/surgery_step/S in good_surgeries)
		if(S.type in banned_surgery_steps)
			good_surgeries -= S
		if(!LAZYLEN(S.allowed_tools))
			good_surgeries -= S
	return good_surgeries

/**
 * Funnily enough, this proc is actually considerably less awful than find_stage.
 * All we have to do is check what surgeries can be done, like surgery mechanics themselves do.
 * Then, build a string telling the user what they can do next.
 */
/obj/machinery/computer/operating/proc/find_next_steps(mob/user, zone)
	. = list()
	for(var/datum/surgery_step/S in get_surgery_steps_without_basetypes())
		if(S.can_use(user, victim, zone, null) && S.is_valid_target(victim))
			var/allowed_tools_by_name = list()
			for(var/tool in S.allowed_tools)
				// Exempt ghetto tools.
				if(S.allowed_tools[tool] < 100)
					continue
				var/obj/tool_path = tool
				allowed_tools_by_name += capitalize(initial(tool_path.name))
			// Please for the love of all that is holy, someone make surgery steps
			// have names so I don't have to do this stupid pretty_type shit.
			. += "[pretty_type(S)]: [english_list(allowed_tools_by_name)]"

#undef OP_COMPUTER_COOLDOWN
