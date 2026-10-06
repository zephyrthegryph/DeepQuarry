/obj/machinery/artifact_harvester
	maintenance_flags = MACHINE_MAINT_STANDARD
	name = "Exotic Particle Harvester"
	icon = 'icons/obj/virology.dmi'
	icon_state = "incubator"	//incubator_on
	anchored = TRUE
	density = TRUE
	idle_power_usage = 50
	active_power_usage = 750
	use_power = USE_POWER_IDLE
	var/harvesting = 0
	var/harvesting_speed = 0
	var/tmp/obj/item/anobattery/inserted_battery
	var/tmp/obj/cur_artifact
	var/tmp/obj/machinery/artifact_scanpad/owned_scanner
	var/last_process = 0
	bubble_icon = "science"
	circuit = /obj/item/circuitboard/artifact_harvester

CAPABILITIES(/obj/machinery/artifact_harvester)
	started_work(step = PROC_REF(work_step))
	ref_one(nameof(owned_scanner), /obj/machinery/artifact_scanpad)
	ref_one(nameof(cur_artifact), /obj)
	interface("XenoarchArtifactHarvester")
	op("harvest", ui_act("harvest"), then(PROC_REF(ui_act_harvest)))
	op("stopharvest", ui_act("stopharvest"), then(PROC_REF(ui_act_stopharvest)))
	op("ejectbattery", ui_act("ejectbattery"), then(PROC_REF(ui_act_ejectbattery)))
	// draining a charged battery asks first
	op("drainbattery", ui_act("drainbattery"),
		asks(/datum/prompt/choice, fields = list("question" = "This action will dump all charge, safety gear is recommended before proceeding", "title" = "Warning", "choices" = list("Continue", "Cancel"), "buttons" = TRUE, "timeout" = 0), step = "k162", when = PROC_REF(battery_has_charge)),
		then(PROC_REF(ui_act_drainbattery)))
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(crowbar_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT - 1), wait(0), then(PROC_REF(screwdriver_used)))
	op("artifact_harvester_use_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_artifact_harvester_use_item)))
	op("open_ui_powered_fingerprint", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(TYPE_PROC_REF(/obj/machinery, op_open_ui_powered_fingerprint)))

/// If you want it to load smoothly, set it's dir to wherever the scanpad is!
/obj/machinery/artifact_harvester/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(owned_scanner), locate_within(get_step(src, dir), /obj/machinery/artifact_scanpad))
	if(!owned_scanner())
		rel_set(src, nameof(owned_scanner), locate_in_list(orange(1, src), /obj/machinery/artifact_scanpad))
	default_apply_parts()

/obj/machinery/artifact_harvester/RefreshParts(limited = 0)
	harvesting_speed = 0
	// Rating goes from 1 to 5 and this bad boy has 5 caps. Let's say we want a normal one to charge a battery in 100 seconds.
	// Every machine process happens every 2 seconds. So, we should have it do 5 charge every second. So 10 charge a process.
	// Tier 3 is commonly availabe. Tier 4/5 is much harder to get.
	// Applying a straight rating * X resultes in either being too strong early or too weak late. So we do a switch depending on rating.
	// This means for a base 500 battery: Tier 1 takes 100 seconds, tier 2 takes 40 seconds, tier 3 takes 20 seconds, tier 4 takes 4 seconds, tier 5 takes 1 second.
	// Tier 4 and 5 may seem overkill, but when you get to the REALLY strong batteries, you'll want them.
	switch(get_part_rating(/obj/item/stock_parts/capacitor))
		if(1)
			harvesting_speed += 2
		if(2)
			harvesting_speed += 5
		if(3)
			harvesting_speed += 10
		if(4)
			harvesting_speed += 50
		if(5)
			harvesting_speed += 100

/obj/machinery/artifact_harvester/proc/interaction_artifact_harvester_use_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(istype(held,/obj/item/anobattery))
		if(!inserted_battery())
			if(!own_bring_in(src, nameof(inserted_battery), held, null, user, TRUE, null, FALSE))
				return TRUE
			to_chat(user, span_blue("You insert [held] into [src]."))
			rel_set(src, nameof(inserted_battery), held)
			SStgui.update_uis(src)
		else
			to_chat(user, span_red("There is already a battery in [src]."))
	if(default_part_replacement(user, held))
		return TRUE
	if(inserted_battery())
		return OP_DECLINE
	return TRUE

/obj/machinery/artifact_harvester/proc/screwdriver_used(datum/act/op/A)
	if(inserted_battery())
		return OP_OK
	return OP_DECLINE

/obj/machinery/artifact_harvester/proc/crowbar_used(datum/act/op/A)
	if(inserted_battery())
		return OP_OK
	return OP_DECLINE

/// The window's data.
/obj/machinery/artifact_harvester/ui_data(datum/act/eval/A)
	var/list/data = list()

	data["info"] = list(
		"no_scanner" = TRUE,
	)
	if(owned_scanner())
		data["info"] = list(
			"no_scanner" = FALSE,
			"harvesting" = harvesting,
			"inserted_battery" = list(),
		)
		if(inserted_battery())
			data["info"]["inserted_battery"] = list(
				"name" = inserted_battery().name,
				"stored_charge" = inserted_battery().stored_charge,
				"capacity" = inserted_battery().capacity,
				"artifact_id" = null
			)
			if(inserted_battery().battery_effect)
				data["info"]["inserted_battery"]["artifact_id"] = inserted_battery().battery_effect.artifact_id || "???"
			else
				data["info"]["inserted_battery"]["artifact_id"] = "N/A"
	return data

/obj/machinery/artifact_harvester/proc/ui_act_harvest(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(A.actor)
	harvest(user)
	return TRUE

/obj/machinery/artifact_harvester/proc/ui_act_stopharvest(datum/act/op/A)
	add_fingerprint(A.actor)
	if(harvesting)
		if(harvesting < 0 && inserted_battery().battery_effect && inserted_battery().battery_effect.activated)
			inserted_battery().battery_effect.ToggleActivate()
		harvesting = 0
		cur_artifact().anchored = FALSE
		cur_artifact().in_use = 0
		rel_clear(src, nameof(/obj/machinery/artifact_harvester::cur_artifact))
		atom_say("Energy harvesting interrupted.")
		icon_state = "incubator"
	return TRUE

/obj/machinery/artifact_harvester/proc/ui_act_ejectbattery(datum/act/op/A)
	add_fingerprint(A.actor)
	if(inserted_battery())
		inserted_battery().forceMove(loc)
		rel_clear(src, nameof(/obj/item/anodevice::inserted_battery))
	return TRUE

/// The drain question is asked only of a battery with an effect and charge in it.
/obj/machinery/artifact_harvester/proc/battery_has_charge(datum/act/op/A)
	var/obj/item/anobattery/B = QDELETED(inserted_battery) ? null : inserted_battery // ALLOW(reads): the battery is read when the button is pressed, never cached
	return B?.battery_effect && B.stored_charge > 0

/obj/machinery/artifact_harvester/proc/ui_act_drainbattery(datum/act/op/A)
	add_fingerprint(A.actor)
	if(inserted_battery())
		if(inserted_battery().battery_effect && inserted_battery().stored_charge > 0)
			var/_answer_k162 = A.step_value("k162")
			if(_answer_k162 == "Continue")
				if(!inserted_battery().battery_effect.activated)
					inserted_battery().battery_effect.ToggleActivate(1)
				harvesting = -1
				set_use_power(USE_POWER_ACTIVE)
				icon_state = "incubator_on"
				atom_say("Warning, battery charge dump commencing.")
		else
			atom_say("Cannot dump energy. Battery is drained of charge already.")
	else
		atom_say("Cannot dump energy. No battery inserted.")
	return TRUE

/obj/machinery/artifact_harvester/proc/harvest(mob/user)
	return harvest_stage(user)

/obj/machinery/artifact_harvester/proc/harvest_stage(mob/user, selected, selection_ready = FALSE)
	if(!inserted_battery())
		atom_say("Cannot harvest. No battery inserted.")
		return
	if(inserted_battery().stored_charge >= inserted_battery().capacity)
		atom_say("Cannot harvest. Battery is full.")
		return

	//locate artifact on analysis pad
	rel_clear(src, nameof(cur_artifact))
	var/articount = 0
	var/obj/analysed
	for(var/obj/A in get_turf(owned_scanner()))
		analysed = A
		if(A.is_anomalous())
			articount++

	if(articount <= 0)
		atom_say("Cannot harvest. No noteworthy energy signature isolated.")
		return

	if(analysed && analysed.in_use)
		atom_say("Cannot harvest. Source already being harvested.")
		return

	if(articount > 1)
		atom_say("Cannot harvest. Too many artifacts on the pad.")
		return

	if(analysed)
		rel_set(src, nameof(cur_artifact), analysed)

		var/list/active_effects //This will be populated when we see if it has the artifact component or the artifact_master var

		var/datum/artifact_master/ScannedMaster = analysed.artifact_master
		if(istype(ScannedMaster))
			active_effects = ScannedMaster.get_all_effects()
		else
			atom_say("Cannot harvest. No energy emitting from source.")
			return
		var/list/effects_to_show = active_effects.Copy()
		for(var/datum/artifact_effect/selected_effect in effects_to_show.Copy()) //We check to see if we're harvestable. If not, remove it from the list.
			if(selected_effect.harvestable == FALSE)
				effects_to_show -= selected_effect

		if(!effects_to_show.len)
			atom_say("Cannot harvest. No harvestable energy emitting from source.")
			return

		var/artifact_selection = selected
		if(!selection_ready)
			open_request(src, /datum/prompt/choice/artifact_harvest_effect, PROC_REF(harvest_effect_chosen), answerer = user, choices = effects_to_show)
			return
		if(isnull(artifact_selection))
			return
		var/datum/artifact_effect/selected_effect
		if(artifact_selection && (artifact_selection in effects_to_show))
			selected_effect = artifact_selection
		else
			atom_say("No selection made. Shutting down harvester.")
			return

		//see if we can clear out an old effect
		//delete it when the ids match to account for duplicate ids having different effects
		if(inserted_battery().battery_effect && inserted_battery().stored_charge <= 0)
			own_clear(inserted_battery(), nameof(/obj/item/anobattery::battery_effect), OWN_DELETE)

		//
		var/datum/artifact_effect/source_effect

		//if we already have charge in the battery, we can only recharge it from the source artifact
		if(inserted_battery().stored_charge > 0)
			var/battery_matches_primary_id = 0
			if(inserted_battery().battery_effect && inserted_battery().battery_effect.artifact_id == ScannedMaster.artifact_id)
				battery_matches_primary_id = 1
			if(battery_matches_primary_id && selected_effect)
				//we're good to recharge the primary effect!
				source_effect = selected_effect

			if(!source_effect)
				atom_say("Cannot harvest. Battery is charged with a different energy signature.")
		else
			source_effect = selected_effect

		if(source_effect)
			harvesting = 1
			set_use_power(USE_POWER_ACTIVE)
			cur_artifact().anchored = TRUE
			cur_artifact().in_use = 1
			icon_state = "incubator_on"
			atom_say("Beginning energy harvesting.")

			//duplicate the artifact's effect datum
			if(!inserted_battery().battery_effect)
				var/effecttype = source_effect.type
				var/datum/artifact_effect/E = new effecttype(inserted_battery())

				//duplicate it's unique settings
				for(var/varname in list("chargelevelmax","artifact_id","effect","effectrange","trigger"))
					E.vars[varname] = source_effect.vars[varname] // ALLOW(api): artifact effect copy

				//copy the new datum into the battery
				rel_set(inserted_battery(), nameof(/obj/item/anobattery::battery_effect), E)
				inserted_battery().stored_charge = 0

/datum/prompt/choice/artifact_harvest_effect
	title = "Effect Selection"
	question = "Which effect do you wish to harvest?"
	timeout = 0

/datum/prompt/choice/artifact_harvest_effect/recheck_extra()
	if(isnull(value))
		return
	var/datum/artifact_effect/selected_effect = value
	if(!istype(selected_effect) || QDELETED(selected_effect))
		return "gone"

/obj/machinery/artifact_harvester/proc/harvest_effect_chosen(datum/act/request/A)
	if(!A.answer)
		return
	. = harvest_effect_apply(A)
	SStgui.update_uis(src)

/obj/machinery/artifact_harvester/proc/harvest_effect_apply(datum/act/request/A)
	return harvest_stage(A.request.answerer, A.request.value, TRUE)

/// Charges or dumps a battery while harvesting (started from its UI); otherwise it sleeps.
/obj/machinery/artifact_harvester/proc/work_step(datum/act/timer/A)
	if(harvesting == 0)
		return PROCESS_KILL
	if(!operable())
		return work_wait_for_power(src)

	if(harvesting > 0)
		//charge at 33% consumption rate
		inserted_battery().stored_charge += harvesting_speed

		//check if we've finished
		if(inserted_battery().stored_charge >= inserted_battery().capacity)
			set_use_power(USE_POWER_IDLE)
			harvesting = 0
			cur_artifact().anchored = FALSE
			cur_artifact().in_use = 0
			rel_clear(src, nameof(cur_artifact))
			src.visible_message(span_bold("[name]") + " states, \"Battery is full.\"")
			icon_state = "incubator"

	else if(harvesting < 0)
		//dump some charge
		inserted_battery().stored_charge -= harvesting_speed

		//do the effect
		if(inserted_battery().battery_effect)
			inserted_battery().battery_effect.periodic_step()

			//if the effect works by touch, activate it on anyone viewing the console
			if(inserted_battery().battery_effect.effect == EFFECT_TOUCH)
				var/list/nearby = viewers(1, src)
				for(var/mob/M in nearby)
					if(M.check_current_machine(src))
						inserted_battery().battery_effect.DoEffectTouch(M)

		//if there's no charge left, finish
		if(inserted_battery().stored_charge <= 0)
			set_use_power(USE_POWER_IDLE)
			inserted_battery().stored_charge = 0
			harvesting = 0
			if(inserted_battery().battery_effect && inserted_battery().battery_effect.activated)
				inserted_battery().battery_effect.ToggleActivate()
			src.visible_message(span_bold("[name]") + " states, \"Battery dump completed.\"")
			icon_state = "incubator"

/// Accessor for the inserted_battery var.
/obj/machinery/artifact_harvester/proc/inserted_battery() as /obj/item/anobattery
	return inserted_battery

/// Accessor for the cur_artifact var.
/obj/machinery/artifact_harvester/proc/cur_artifact() as /obj
	return cur_artifact

/// Accessor for the owned_scanner var.
/obj/machinery/artifact_harvester/proc/owned_scanner() as /obj/machinery/artifact_scanpad
	return owned_scanner
