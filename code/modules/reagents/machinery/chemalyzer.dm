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
	clicksound = SFX_BUTTON
	circuit = /obj/item/circuitboard/chemical_analyzer
	var/list/found_reagents

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/chemical_analyzer/Initialize(mapload)
	. = ..()
	default_apply_parts()

/// The analyzer draws its working state while an analysis claims it.
/obj/machinery/chemical_analyzer/draw(datum/look/look)
	..()
	look.state(op_claimed(src) ? "chem_analyzer-working" : "chem_analyzer")

MSG_DEF_SELF(chemical_analyzer/analyzing, "Analyzing %I%, please stand by...")

/// The sample left the scan before it was done.
/obj/machinery/chemical_analyzer/proc/scan_failed(datum/act/op/A)
	to_chat(A.actor, span_warning("Sample moved outside of scan range, please try again and remain still."))
	update_icon()

/// Two seconds later: identify a chemical mystery and show what the container holds.
/obj/machinery/chemical_analyzer/proc/scan_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	// First, identify it if it isn't already.
	if(!held.is_identified(IDENTITY_FULL))
		var/datum/identification/ID = held.identity
		if(ID.identification_type == IDENTITY_TYPE_CHEMICAL) // This only solves chemical-based mysteries.
			held.identify(IDENTITY_FULL, user)

	// Now tell us everything that is inside.
	if(held.reagents && held.reagents.reagent_list.len)
		found_reagents = list() // a fresh list per analysis (the old Cut() ran on a list nothing had made)
		for(var/datum/reagent/R in held.reagents.reagent_list)
			if(!R.name)
				continue
			found_reagents[R.id] = R.volume
		tgui_interact(user)
	else
		to_chat(user, span_warning("Nothing detected in [held]"))

	update_icon()
	return OP_OK

CAPABILITIES(/obj/machinery/chemical_analyzer)
	op("analyze", item(/obj/item/reagent_containers), label("Analyze"), begins(MSG(chemical_analyzer/analyzing)), wait(2 SECONDS), claims(),
		on_interrupt(PROC_REF(scan_failed)), then(PROC_REF(scan_done)))
	interface("ChemAnalyzerPro")
	ui_shape(scannedReagents = list_of(row()), beakerTotal = num(), beakerMax = num())

/obj/machinery/chemical_analyzer/ui_data(datum/act/eval/A)
	var/list/data = list()

	var/total_vol = 0
	var/list/reagents_sent = list()
	var/obj/item/reagent_containers/glass/beaker/large/beaker_path = /obj/item/reagent_containers/glass/beaker/large
	for(var/ID in found_reagents)
		var/datum/reagent/R = SSchemistry.ready().chemical_reagents[ID]
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
		subdata["beakerAmount"] = LAZYACCESS(found_reagents, ID)
		total_vol += LAZYACCESS(found_reagents, ID)
		SSinternal_wiki.assemble_reaction_data(subdata, R)
		// Send as a big list of lists
		reagents_sent += list(subdata)
	data["scannedReagents"] = reagents_sent
	data["beakerTotal"] = total_vol
	data["beakerMax"] = initial(beaker_path.volume)

	return data
