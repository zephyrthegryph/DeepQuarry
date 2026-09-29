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

DECLARE_REF(/obj/machinery/computer/operating, "table", PAIR, "computer")

EXTEND_INTERACTIONS(/obj/machinery/computer/operating, \
	INTERACT_HAND_UNGATED(null, TYPE_PROC_REF(/obj/machinery, interaction_open_ui_powered_fingerprint)), \
	INTERACT_SILICON("Use", TYPE_PROC_REF(/obj/machinery, interaction_open_ui_powered_fingerprint)), \
)

DECLARE_UI(/obj/machinery/computer/operating, "OperatingComputer", UI_TITLE("Patient Monitor"))

UI_DATA_REPLACE(/obj/machinery/computer/operating, "verbose:num", "spo2Alarm:num", "choice", "health=healthAnnounce:num", "crit:num", "healthAlarm:num", "spo2:num", "merge:ui_data_obj_machinery_computer_operating{hasOccupant:num,occupant:list}")

/// The computed part of /obj/machinery/computer/operating's window data (declared on its UI_DATA row).
/obj/machinery/computer/operating/proc/ui_data_obj_machinery_computer_operating(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
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

/obj/machinery/computer/operating/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if((ui.user.contents.Find(src) || (in_range(src, ui.user) && istype(src.loc, /turf))) || (istype(ui.user, /mob/living/silicon)))
		ui.user.set_machine(src)
	return TRUE

UI_ACT(/obj/machinery/computer/operating, "verboseOn", ui_act_verboseon)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_verboseon)
	. = TRUE
	verbose = TRUE

UI_ACT(/obj/machinery/computer/operating, "verboseOff", ui_act_verboseoff)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_verboseoff)
	. = TRUE
	verbose = FALSE

UI_ACT(/obj/machinery/computer/operating, "healthOn", ui_act_healthon)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_healthon)
	. = TRUE
	healthAnnounce = TRUE

UI_ACT(/obj/machinery/computer/operating, "healthOff", ui_act_healthoff)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_healthoff)
	. = TRUE
	healthAnnounce = FALSE

UI_ACT(/obj/machinery/computer/operating, "critOn", ui_act_criton)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_criton)
	. = TRUE
	crit = TRUE

UI_ACT(/obj/machinery/computer/operating, "critOff", ui_act_critoff)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_critoff)
	. = TRUE
	crit = FALSE

UI_ACT(/obj/machinery/computer/operating, "spo2On", ui_act_spo2on)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_spo2on)
	. = TRUE
	spo2 = TRUE

UI_ACT(/obj/machinery/computer/operating, "spo2Off", ui_act_spo2off)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_spo2off)
	. = TRUE
	spo2 = FALSE

UI_ACT(/obj/machinery/computer/operating, "spo2_adj", ui_act_spo2_adj, UI_ARG_NUM("new", 0, 100))
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_spo2_adj)
	. = TRUE
	spo2Alarm = params["new"]

UI_ACT(/obj/machinery/computer/operating, "choiceOn", ui_act_choiceon)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_choiceon)
	. = TRUE
	choice = TRUE

UI_ACT(/obj/machinery/computer/operating, "choiceOff", ui_act_choiceoff)
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_choiceoff)
	. = TRUE
	choice = FALSE

UI_ACT(/obj/machinery/computer/operating, "health_adj", ui_act_health_adj, UI_ARG_NUM("new", -100, 100))
UI_ACT_PROC(/obj/machinery/computer/operating, ui_act_health_adj)
	. = TRUE
	healthAlarm = params["new"]

/obj/machinery/computer/operating/machine_step()
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

DECLARE_REF(/obj/machinery/computer/operating, "victim", HELD, null)
