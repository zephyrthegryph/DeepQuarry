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
		rel_set(src, nameof(table), locate(/obj/machinery/optable, get_step(src, direction)))
		if(table)
			rel_set(table, nameof(table.computer), src)
			break

/obj/machinery/computer/operating/relations()
	. = ..()
	. += rel_one(nameof(table), back = nameof(/obj/machinery/optable::computer))

EXTEND_INTERACTIONS(/obj/machinery/computer/operating, \
	INTERACT_HAND_UNGATED(null, TYPE_PROC_REF(/obj/machinery, interaction_open_ui_powered_fingerprint)), \
	INTERACT_SILICON("Use", TYPE_PROC_REF(/obj/machinery, interaction_open_ui_powered_fingerprint)), \
)

CAPABILITIES(/obj/machinery/computer/operating)
	interface("OperatingComputer", title = "Patient Monitor")
	op("verboseOn", ui_act("verboseOn"), then(PROC_REF(ui_act_verboseon)))
	op("verboseOff", ui_act("verboseOff"), then(PROC_REF(ui_act_verboseoff)))
	op("healthOn", ui_act("healthOn"), then(PROC_REF(ui_act_healthon)))
	op("healthOff", ui_act("healthOff"), then(PROC_REF(ui_act_healthoff)))
	op("critOn", ui_act("critOn"), then(PROC_REF(ui_act_criton)))
	op("critOff", ui_act("critOff"), then(PROC_REF(ui_act_critoff)))
	op("spo2On", ui_act("spo2On"), then(PROC_REF(ui_act_spo2on)))
	op("spo2Off", ui_act("spo2Off"), then(PROC_REF(ui_act_spo2off)))
	op("spo2_adj", ui_act("spo2_adj", arg("new", num(0, 100))), then(PROC_REF(ui_act_spo2_adj)))
	op("choiceOn", ui_act("choiceOn"), then(PROC_REF(ui_act_choiceon)))
	op("choiceOff", ui_act("choiceOff"), then(PROC_REF(ui_act_choiceoff)))
	op("health_adj", ui_act("health_adj", arg("new", num(-100, 100))), then(PROC_REF(ui_act_health_adj)))
	extend(TAG_UI, then(PROC_REF(ui_attended), early = TRUE))

/obj/machinery/computer/operating/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["verbose"] = verbose
	data["spo2Alarm"] = spo2Alarm
	data["choice"] = choice
	data["health"] = healthAnnounce
	data["crit"] = crit
	data["healthAlarm"] = healthAlarm
	data["spo2"] = spo2
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
		qdel(D)
		if(ishuman(occupant) && occupant.dna)
			occupantData["bloodType"] = occupant.dna.b_type
			occupantData["surgery"] = build_surgery_list(user)

	data["occupant"] = occupantData

	return data

/// Whoever works the monitor from within reach, or a silicon, has it as their machine (the old window guard's side effect).
/obj/machinery/computer/operating/proc/ui_attended(datum/act/op/A)
	var/mob/user = A.actor
	if((user.contents.Find(src) || (in_range(src, user) && istype(src.loc, /turf))) || (istype(user, /mob/living/silicon)))
		user.set_machine(src)
	return OP_OK

/obj/machinery/computer/operating/proc/ui_act_verboseon(datum/act/op/A)
	. = TRUE
	verbose = TRUE

/obj/machinery/computer/operating/proc/ui_act_verboseoff(datum/act/op/A)
	. = TRUE
	verbose = FALSE

/obj/machinery/computer/operating/proc/ui_act_healthon(datum/act/op/A)
	. = TRUE
	healthAnnounce = TRUE

/obj/machinery/computer/operating/proc/ui_act_healthoff(datum/act/op/A)
	. = TRUE
	healthAnnounce = FALSE

/obj/machinery/computer/operating/proc/ui_act_criton(datum/act/op/A)
	. = TRUE
	crit = TRUE

/obj/machinery/computer/operating/proc/ui_act_critoff(datum/act/op/A)
	. = TRUE
	crit = FALSE

/obj/machinery/computer/operating/proc/ui_act_spo2on(datum/act/op/A)
	. = TRUE
	spo2 = TRUE

/obj/machinery/computer/operating/proc/ui_act_spo2off(datum/act/op/A)
	. = TRUE
	spo2 = FALSE

/obj/machinery/computer/operating/proc/ui_act_spo2_adj(datum/act/op/A, value)
	. = TRUE
	spo2Alarm = value

/obj/machinery/computer/operating/proc/ui_act_choiceon(datum/act/op/A)
	. = TRUE
	choice = TRUE

/obj/machinery/computer/operating/proc/ui_act_choiceoff(datum/act/op/A)
	. = TRUE
	choice = FALSE

/obj/machinery/computer/operating/proc/ui_act_health_adj(datum/act/op/A, value)
	. = TRUE
	healthAlarm = value

/obj/machinery/computer/operating/machine_step()
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

