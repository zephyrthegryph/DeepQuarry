/obj/item/mining_scanner
	name = "deep scan device"
	desc = "A complex device used to locate ore deep underground."
	icon = 'icons/obj/device.dmi'
	icon_state = "deep_scan_device"
	item_state = "electronic"
	MATERIAL_BULK(MAT_STEEL, 150)
	var/scan_time = 2 SECONDS
	var/range = 2
	var/exact = FALSE
	var/sediment_scan = TRUE

TRACKED(/obj/item/mining_scanner, sediment_scan)
TRACKED(/obj/item/mining_scanner, range)
TRACKED(/obj/item/mining_scanner, scan_time)
TRACKED(/obj/item/mining_scanner, exact)

CAPABILITIES(/obj/item/mining_scanner)
	held_verb(/obj/item/mining_scanner/proc/toggle_sediment_scan, SLOT_ANY_CARRIED)
	op("scan", in_hand(), label("Scan deposits"), then(PROC_REF(scan_started), early = TRUE), wait(PROC_REF(scan_delay)), then(PROC_REF(scanned)))
	op("toggle_sediment", menu(), label("Toggle Sediment Scan"), needs(carried()), then(PROC_REF(sediment_toggled)))

/obj/item/mining_scanner/proc/scan_started(datum/act/op/A)
	to_chat(A.actor, span_notice("You begin sweeping \the [src] about, scanning for metal deposits."))
	play_sfx(src, SFX_ITEMS_GOGGLES_CHARGE)
	return OP_OK

/obj/item/mining_scanner/proc/scan_delay(datum/act/op/A)
	return scan_time

/obj/item/mining_scanner/proc/scanned(datum/act/op/A)
	ScanTurf(get_turf(A.actor), A.actor)
	return OP_OK

/obj/item/mining_scanner/proc/toggle_sediment_scan()
	set name = "Toggle Sediment Scan"
	set category = VERB_CAT_OBJECT
	set src in usr
	perform_op(usr, src, "toggle_sediment", null, ORIGIN_VERB)

/obj/item/mining_scanner/proc/sediment_toggled(datum/act/op/A)
	to_chat(A.actor, span_notice("\The [src] will [sediment_scan ? "no longer" : "now"] scan for reagents."))
	set_sediment_scan(!sediment_scan)
	return OP_OK

/obj/item/mining_scanner/proc/ScanTurf(atom/target, mob/user)
	var/list/metals = list(
		"surface minerals" = 0,
		"industrial metals" = 0,
		"precious metals" = 0,
		"precious gems" = 0,
		"nuclear fuel" = 0,
		"exotic matter" = 0,
		"anomalous matter" = 0
		)

	var/list/reagents_found = list()
	var/turf/Turf = get_turf(target)

	for(var/turf/simulated/T in range(range, Turf))

		if(!(T.turf_resource_types & TURF_HAS_MINERALS))
			continue

		for(var/metal in T.resources)
			var/ore_type

			switch(metal)
				if(ORE_SAND, ORE_CARBON, ORE_MARBLE, ORE_QUARTZ)				ore_type = "surface minerals"
				if(ORE_HEMATITE, ORE_TIN, ORE_COPPER, ORE_BAUXITE, ORE_LEAD)	ore_type = "industrial metals"
				if(ORE_GOLD, ORE_SILVER, ORE_RUTILE)							ore_type = "precious metals"
				if(ORE_DIAMOND, ORE_PAINITE)									ore_type = "precious gems"
				if(ORE_URANIUM)													ore_type = "nuclear fuel"
				if(ORE_PHORON, ORE_PLATINUM, ORE_MHYDROGEN)						ore_type = "exotic matter"
				if(ORE_VERDANTIUM, ORE_VOPAL)									ore_type = "anomalous matter"

			if(ore_type)
				metals[ore_type] += T.resources[metal]
			if(islist(GLOB.deepore_fracking_reagents[metal]))
				for(var/reg_id in GLOB.deepore_fracking_reagents[metal])
					reagents_found[reg_id] += 1

	var/message = "[icon2html(src, user.client)] " + span_infoplain("The scanner beeps and displays a readout:")

	for(var/ore_type in metals)
		var/result = "no sign"

		if(!exact)
			switch(metals[ore_type])
				if(1 to 25) result = "trace amounts"
				if(26 to 75) result = "significant amounts"
				if(76 to INFINITY) result = "huge quantities"

		else
			result = metals[ore_type]

		message += "<br>" + span_notice("- [result] of [ore_type].")

	if(sediment_scan && reagents_found.len)
		message += "<br>" + span_infoplain("Sediment sample contains: ")
		for(var/reg_id in reagents_found)
			var/amnt = reagents_found[reg_id]
			var/minimum = 25
			if(amnt > minimum || exact)
				var/datum/reagent/R = SSchemistry.ready().chemical_reagents[reg_id]
				var/ds = ""
				if(amnt <= minimum && exact)
					ds = "miniscule "
				else if(amnt <= 40)
					ds = "low "
				else if(amnt >= 120 && exact)
					ds = "massive "
				else if(amnt >= 80)
					ds = "high "
				message += "<br>" + span_notice("- [ds][R.name]")

	to_chat(user, message)

/obj/item/mining_scanner/advanced/get_mechanics_info(list/additional_information)
	return ..(list("This scanner has variable range. Drills dig in 5x5.") + additional_information)

/obj/item/mining_scanner/advanced
	name = "advanced ore detector"
	desc = "An advanced device used to locate ore deep underground."
	MATERIAL_BULK(MAT_STEEL, 150)
	scan_time = 0.5 SECONDS
	exact = TRUE

CAPABILITIES(/obj/item/mining_scanner/advanced)
	held_verb(/obj/item/mining_scanner/advanced/proc/set_scanner_range, SLOT_ANY_CARRIED)
	op("set_range", inputs(hand(), menu()), gesture(GESTURE_ALT), label("Set Scanner Range"),
		needs(req_adjacent(), req_on_origin(ORIGIN_VERB | ORIGIN_MENU, carried())),
		asks(/datum/prompt/choice, keeps = 0, fields = list("timeout" = 0, "question" = "Scanner Range", "title" = "Pick a range to scan. ", "choices" = list(0,1,2,3,4,5,6,7))), then(PROC_REF(range_picked)))

/obj/item/mining_scanner/advanced/proc/set_scanner_range()
	set name = "Set Scanner Range"
	set category = VERB_CAT_OBJECT
	set src in usr
	perform_op(usr, src, "set_range", null, ORIGIN_VERB)

/obj/item/mining_scanner/advanced/proc/range_picked(datum/act/op/A)
	var/datum/prompt/choice/picked = A.answer
	// The advanced handheld's original zero choice leaves its range unchanged.
	if(picked.value)
		set_range(picked.value)
		to_chat(A.actor, span_notice("Scanner will now look up to [range] tile(s) away."))
	return OP_OK
