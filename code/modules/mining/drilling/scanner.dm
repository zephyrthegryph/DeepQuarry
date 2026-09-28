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

DECLARE_INTERACTIONS(/obj/item/mining_scanner, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_VERB("Toggle Sediment Scan", PROC_REF(mining_scanner_verb_toggle_sediment)), \
)

/// Old attack_self.
/obj/item/mining_scanner/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You begin sweeping \the [src] about, scanning for metal deposits."))
	play_sfx(src, SFX_ITEMS_GOGGLES_CHARGE)

	om_task_timed(user, scan_time, src, src, PROC_REF(sweep_done), list(user))
	return TRUE

/obj/item/mining_scanner/proc/sweep_done(mob/user)
	ScanTurf(get_turf(user), user)

/// Old Toggle Sediment Scan verb.
/obj/item/mining_scanner/proc/mining_scanner_verb_toggle_sediment(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("\The [src] will [sediment_scan ? "no longer" : "now"] scan for reagents."))
	sediment_scan = !sediment_scan

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
				var/datum/reagent/R = chemistry_service().chemical_reagents[reg_id]
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

EXTEND_INTERACTIONS(/obj/item/mining_scanner/advanced, \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
	INTERACT_VERB("Set Scanner Range", PROC_REF(adv_mining_scanner_verb_range), REQ_IN_INVENTORY), \
)

/// Old click_alt.
/obj/item/mining_scanner/advanced/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	adv_mining_scanner_verb_range(user)
	return TRUE

/// Old Set Scanner Range verb.
/obj/item/mining_scanner/advanced/proc/adv_mining_scanner_verb_range(mob/user, obj/item/held, datum/interaction/interaction)
	var/custom_range = rerun_ask(user, "k120", PROC_REF(adv_mining_scanner_verb_range), args, /datum/om/prompt/choice, message = "Scanner Range", title = "Pick a range to scan. ", choices = list(0,1,2,3,4,5,6,7))
	if(isnull(custom_range))
		return
	if(custom_range)
		range = custom_range
		to_chat(user, span_notice("Scanner will now look up to [range] tile(s) away."))
