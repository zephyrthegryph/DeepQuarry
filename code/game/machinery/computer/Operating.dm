#define OP_COMPUTER_COOLDOWN 6 SECONDS

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
		rel_set(src, nameof(table), locate(/obj/machinery/optable, get_step(src, direction)))
		if(table)
			rel_set(table, nameof(table.computer), src)
			break

/obj/machinery/computer/operating/relations()
	. = ..()
	. += rel_one(nameof(table), back = nameof(/obj/machinery/optable::computer))

TRACKED(/obj/machinery/computer/operating, verbose)
TRACKED(/obj/machinery/computer/operating, spo2Alarm)
TRACKED(/obj/machinery/computer/operating, choice)
TRACKED(/obj/machinery/computer/operating, healthAnnounce)
TRACKED(/obj/machinery/computer/operating, crit)
TRACKED(/obj/machinery/computer/operating, healthAlarm)
TRACKED(/obj/machinery/computer/operating, spo2)

CAPABILITIES(/obj/machinery/computer/operating)
	started_work(step = PROC_REF(work_step))
	contributes(STAT_OPERABLE, TYPE_PROC_REF(/obj/machinery, stat_bits_allow), reads = list("stat"))
	interface("OperatingComputer", title = "Patient Monitor")
	extend("ui_open", needs(req_operable()), then(PROC_REF(control_fingerprinted)))
	op("verboseOn", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(verboseOn)))
	op("verboseOff", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(verboseOff)))
	op("healthOn", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(healthOn)))
	op("healthOff", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(healthOff)))
	op("critOn", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(critOn)))
	op("critOff", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(critOff)))
	op("spo2On", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(spo2On)))
	op("spo2Off", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(spo2Off)))
	op("choiceOn", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(choiceOn)))
	op("choiceOff", ui_act(), then(PROC_REF(control_used)), then(PROC_REF(choiceOff)))
	op("spo2_adj", ui_act(arg("new", num(0, 100))), then(PROC_REF(control_value_used)), then(PROC_REF(spo2_adjusted)))
	op("health_adj", ui_act(arg("new", num(-100, 100))), then(PROC_REF(control_value_used)), then(PROC_REF(health_adjusted)))

/obj/machinery/computer/operating/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list("verbose" = verbose, "spo2Alarm" = spo2Alarm, "choice" = choice, "health" = healthAnnounce, "crit" = crit, "healthAlarm" = healthAlarm, "spo2" = spo2)
	var/mob/living/carbon/human/occupant
	if(table)
		occupant = table.victim
	data["hasOccupant"] = occupant ? 1 : 0
	var/list/occupantData = list()

	if(occupant)
		occupantData["name"] = occupant.name
		occupantData["stat"] = occupant.stat
		occupantData["vitality"] = round(occupant.vitality() * 100)
		occupantData["paralysis"] = occupant.status_units(EFFECT_PARALYZED)
		var/datum/diagnosis/D = occupant.diagnose(/datum/diagnostic_profile/operating_computer)
		occupantData["diagnosis"] = D.report_data()
		spent(D)
		if(ishuman(occupant) && occupant.dna)
			occupantData["bloodType"] = occupant.dna.b_type
			occupantData["surgery"] = build_surgery_list(user)

	data["occupant"] = occupantData

	return data

/obj/machinery/computer/operating/proc/control_fingerprinted(datum/act/op/A)
	add_fingerprint(A.actor)
	return OP_OK

/obj/machinery/computer/operating/proc/control_used(datum/act/op/A)
	var/mob/user = A.actor
	if(user.contents.Find(src) || (in_range(src, user) && isturf(loc)) || issilicon(user))
		user.set_machine(src)
	return OP_OK

/obj/machinery/computer/operating/proc/control_value_used(datum/act/op/A, value)
	return control_used(A)

/obj/machinery/computer/operating/proc/verboseOn(datum/act/op/A)
	set_verbose(TRUE)
	return OP_OK

/obj/machinery/computer/operating/proc/verboseOff(datum/act/op/A)
	set_verbose(FALSE)
	return OP_OK

/obj/machinery/computer/operating/proc/healthOn(datum/act/op/A)
	set_healthAnnounce(TRUE)
	return OP_OK

/obj/machinery/computer/operating/proc/healthOff(datum/act/op/A)
	set_healthAnnounce(FALSE)
	return OP_OK

/obj/machinery/computer/operating/proc/critOn(datum/act/op/A)
	set_crit(TRUE)
	return OP_OK

/obj/machinery/computer/operating/proc/critOff(datum/act/op/A)
	set_crit(FALSE)
	return OP_OK

/obj/machinery/computer/operating/proc/spo2On(datum/act/op/A)
	set_spo2(TRUE)
	return OP_OK

/obj/machinery/computer/operating/proc/spo2Off(datum/act/op/A)
	set_spo2(FALSE)
	return OP_OK

/obj/machinery/computer/operating/proc/choiceOn(datum/act/op/A)
	set_choice(TRUE)
	return OP_OK

/obj/machinery/computer/operating/proc/choiceOff(datum/act/op/A)
	set_choice(FALSE)
	return OP_OK

/obj/machinery/computer/operating/proc/spo2_adjusted(datum/act/op/A, value)
	set_spo2Alarm(value)
	return OP_OK

/obj/machinery/computer/operating/proc/health_adjusted(datum/act/op/A, value)
	set_healthAlarm(value)
	return OP_OK

/obj/machinery/computer/operating/proc/work_step(datum/act/timer/A)
	if(!table || !table.check_victim())
		rel_clear(src, nameof(victim))
		patientName = null
		return PROCESS_KILL
	if(table && table.victim)
		if(verbose)
			if(patientName!=table.victim.name)
				patientName=table.victim.name
				atom_say("New patient detected, loading stats")
				rel_set(src, nameof(victim), table.victim)
				atom_say("[victim.real_name], [victim.dna.b_type] blood, [victim.stat ? "Non-Responsive" : "Awake"]")
				SStgui.update_uis(src)
			if(COOLDOWN_FINISHED(src, nextTick))
				COOLDOWN_START(src, nextTick, OP_COMPUTER_COOLDOWN)
				if(crit && victim.is_critical())
					play_sfx(src.loc, SFX_MACHINES_DEFIB_SUCCESS)
				var/saturation = victim.body?.oxygenation()
				if(spo2 && !isnull(saturation) && saturation < spo2Alarm)
					play_sfx(src.loc, SFX_MACHINES_DEFIB_SAFETYOFF)
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
