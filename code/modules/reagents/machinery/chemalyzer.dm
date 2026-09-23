// Detects reagents inside most containers, and acts as an infinite identification system for reagent-based unidentified objects.

/obj/machinery/chemical_analyzer
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "chem analyzer PRO"
	desc = "New and improved! Used to precisely scan chemicals and other liquids inside various containers. \
	It can also identify the liquid contents of unknown objects and their chemical breakdowns."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "chem_analyzer"
	density = TRUE
	anchored = TRUE
	use_power = TRUE
	idle_power_usage = 20
	clicksound = "button"
	circuit = /obj/item/circuitboard/chemical_analyzer
	var/analyzing = FALSE
	var/list/found_reagents = list()

/obj/machinery/chemical_analyzer/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/chemical_analyzer/update_icon()
	icon_state = "chem_analyzer[analyzing ? "-working":""]"

/obj/machinery/chemical_analyzer/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/chemical_analyzer_scan,
		/datum/interaction/machine_hand/ungated/chemical_analyzer_open_ui,
	)
	..()

/datum/interaction/machine_item/chemical_analyzer_scan
	id = "chemical_analyzer_scan"
	name = "Analyze"
	held_type = /obj/item/reagent_containers
	effect = /obj/machinery/chemical_analyzer/proc/interaction_scan

/obj/machinery/chemical_analyzer/proc/interaction_scan(mob/user, obj/item/held, datum/interaction/interaction)
	analyzing = TRUE
	update_icon()
	to_chat(user, span_notice("Analyzing \the [held], please stand by..."))

	if(!do_after(user, 2 SECONDS, src))
		to_chat(user, span_warning("Sample moved outside of scan range, please try again and remain still."))
		analyzing = FALSE
		update_icon()
		return TRUE

	// First, identify it if it isn't already.
	if(!held.is_identified(IDENTITY_FULL))
		var/datum/identification/ID = held.identity
		if(ID.identification_type == IDENTITY_TYPE_CHEMICAL) // This only solves chemical-based mysteries.
			held.identify(IDENTITY_FULL, user)

	// Now tell us everything that is inside.
	if(held.reagents && held.reagents.reagent_list.len)
		found_reagents.Cut()
		for(var/datum/reagent/R in held.reagents.reagent_list)
			if(!R.name)
				continue
			found_reagents[R.id] = R.volume
		tgui_interact(user)
	else
		to_chat(user, span_warning("Nothing detected in [held]"))

	analyzing = FALSE
	update_icon()
	return TRUE

/obj/machinery/chemical_analyzer/screwdriver_act(mob/user, obj/item/tool)
	return ..()

/obj/machinery/chemical_analyzer/crowbar_act(mob/user, obj/item/tool)
	return ..()

/datum/interaction/machine_hand/ungated/chemical_analyzer_open_ui
	id = "chemical_analyzer_open_ui"
	name = "Use"
	category = INTERACTION_CAT_CONFIGURE
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/chemical_analyzer/proc/has_results, null))
	effect = /obj/machinery/chemical_analyzer/proc/interaction_open_ui

/obj/machinery/chemical_analyzer/proc/has_results(mob/actor, atom/target, obj/item/held)
	return length(found_reagents) > 0

/obj/machinery/chemical_analyzer/proc/interaction_open_ui(mob/user, obj/item/held, datum/interaction/interaction)
	tgui_interact(user) // Show last analysis
	return TRUE

/obj/machinery/chemical_analyzer/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "ChemAnalyzerPro", name)
		ui.open()

/obj/machinery/chemical_analyzer/tgui_data(mob/user)
	var/list/data = list()

	var/total_vol = 0
	var/list/reagents_sent = list()
	var/obj/item/reagent_containers/glass/beaker/large/beaker_path = /obj/item/reagent_containers/glass/beaker/large
	for(var/ID in found_reagents)
		var/datum/reagent/R = SSchemistry.chemical_reagents[ID]
		if(!R)
			continue
		var/list/subdata = list()
		subdata["title"] = R.name
		SSinternal_wiki.add_icon(subdata, initial(beaker_path.icon), initial(beaker_path.icon_state), R.color)
		// Get internal data
		subdata["description"] = R.description
		subdata["addictive"] = 0
		subdata["cooling_mod"] = R.coolant_modifier
		if(R.id in get_addictive_reagents(ADDICT_ALL))
			subdata["addictive"] = TRUE
		subdata["industrial_use"] = R.industrial_use
		subdata["supply_points"] = R.supply_conversion_value ? R.supply_conversion_value : 0
		var/value = R.supply_conversion_value * REAGENTS_PER_SHEET * SSsupply.points_per_money
		value = FLOOR(value * 100,1) / 100 // Truncate decimals
		subdata["market_price"] = value
		subdata["sintering"] = SSinternal_wiki.assemble_sintering(GLOB.reagent_sheets[R.id])
		subdata["overdose"] = R.overdose
		subdata["flavor"] = R.taste_description
		subdata["allergen"] = assembly_allergy_list(R.allergen_type, R.medallergen_type)
		subdata["beakerAmount"] = found_reagents[ID]
		total_vol += found_reagents[ID]
		SSinternal_wiki.assemble_reaction_data(subdata, R)
		// Send as a big list of lists
		reagents_sent += list(subdata)
	data["scannedReagents"] = reagents_sent
	data["beakerTotal"] = total_vol
	data["beakerMax"] = initial(beaker_path.volume)

	return data
