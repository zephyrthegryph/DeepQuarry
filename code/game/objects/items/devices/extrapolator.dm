/obj/item/extrapolator
	name = "virus extrapolator"
	icon = 'icons/obj/device.dmi'
	icon_state = "extrapolator_scan"
	desc = "A bulky scanning device, used to extract genetic material of potential pathogens."
	description_info = "Use on hand to change between SCAN and EXTRACT mode."
	item_flags = NOBLUDGEON
	slot_flags = SLOT_BELT
	w_class = ITEMSIZE_NORMAL
	/// Whether the extrapolator is curently in use
	var/using = FALSE
	/// Whether the extrapolator is curently in SCAN or EXTRACT mode
	var/scan = TRUE
	/// The scanning module installed in the extrapolator. Used to determine extraction speed, and the stealthiest virus that's possible to extract.
	var/obj/item/stock_parts/scanning_module/scanner
	/// A list of advance IDs that this extrapolator has already extracted.
	var/list/extracted_ids
	/// How long it takes for the extrapolator to extract a virus.
	var/extract_time = 10 SECONDS
	/// How long it tkaes for the extrapolator to isolate a symptom.
	var/isolate_time = 15 SECONDS
	/// The extrapolator can extract any virus with a stealth below this value.
	var/maximum_stealth = 3
	/// The extrapolator can extract any symptom with a stealth below this value.
	var/maximum_level = 5
	/// The typepath of the default scanning module that will generate in the extrapolator, if it starts with none.
	var/default_scanning_module = /obj/item/stock_parts/scanning_module
	/// Cooldown for when the extrapolator can be used next.
	COOLDOWN_DECLARE(usage_cooldown)

/obj/item/extrapolator/Initialize(mapload, obj/item/stock_parts/scanning_module/starting_scanner)
	. = ..()
	starting_scanner = starting_scanner || default_scanning_module
	if(ispath(starting_scanner, /obj/item/stock_parts/scanning_module))
		scanner = new starting_scanner(src)
	else if(istype(starting_scanner))
		starting_scanner.forceMove(src)
		scanner = starting_scanner

	refresh_parts()

/obj/item/extrapolator/get_interactions()
	var/static/list/L = list(
		INTERACT_INSERT(/obj/item/stock_parts/scanning_module, PROC_REF(interaction_item), "Install"),
		INTERACT_USE("Toggle mode", PROC_REF(interaction_self)),
	)
	return L

/obj/item/extrapolator/proc/interaction_item(mob/user, obj/item/item, datum/interaction/interaction)
	if(!scanner)
		user.drop_item()
		item.forceMove(src)
		scanner = item
		to_chat(user, span_notice("You install \the [scanner] in [src]."))
		refresh_parts()
	else
		to_chat(user, span_notice("[src] already has \the [scanner] installed."))
	return TRUE

/obj/item/extrapolator/screwdriver_act(mob/user, obj/item/tool)
	if(!scanner)
		to_chat(user, span_warning("\The [src] has no scanner to remove!"))
		return ITEM_INTERACT_BLOCKING
	to_chat(user, span_notice("You remove \the [scanner] from \the [src]."))
	scanner.forceMove(drop_location())
	scanner = null
	playsound(src, tool.usesound, 50, 1)
	return ITEM_INTERACT_SUCCESS

/obj/item/extrapolator/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	playsound(src, 'sound/machines/click.ogg', 50, TRUE)
	if(scan)
		icon_state = "extrapolator_sample"
		scan = FALSE
		to_chat(user, span_notice("You remove the probe from the device and set it to EXTRACT."))
	else
		icon_state = "extrapolator_scan"
		scan = TRUE
		to_chat(user, span_notice("You put the probe back into the device and set it to SCAN."))
	return TRUE

/obj/item/extrapolator/examine(mob/user)
	. = ..()
	if(in_range(user, src) || isobserver(user))
		if(!scanner)
			. += span_notice("The scanner is missing.")
		else
			. += span_notice("A class " + span_bold("[scanner.rating]") + " scanning module is installed. It is <i>screwed</i> in place.")
			// . += span_notice("Can detect diseases below stealth " + span_bold("[maximum_stealth]") + ".")
			. += span_notice("Can extract diseases in " + span_bold("[DisplayTimeText(extract_time)]") + ".")
			. += span_notice("Can isolate symptoms <b>[maximum_level >= 9 ? "of any level" : "below level [maximum_level]"]</b>, in <b>[DisplayTimeText(isolate_time)]</b>.")

/obj/item/extrapolator/proc/refresh_parts()
	if(!scanner)
		return
	var/effective_scanner_rating = scanner.rating +1
	extract_time = (10 SECONDS) / effective_scanner_rating
	isolate_time = (15 SECONDS) / effective_scanner_rating
	// maximum_stealth = scanner.rating + 2
	maximum_level = scanner.rating + 5

/obj/item/extrapolator/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return ITEM_INTERACT_FAILURE

/obj/item/extrapolator/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!proximity_flag && !scan)
		return
	if(using)
		to_chat(user, span_warning("[icon2html(src, user)] The extrapolator is already in use."))
		return
	if(!COOLDOWN_FINISHED(src, usage_cooldown))
		to_chat(user, span_warning("[icon2html(src, user)] The extrapolator is still recharging!"))
		return
	if(scanner)
		var/list/result = target?.extrapolator_act(user, src, dry_run = TRUE)
		var/list/diseases = result && result[EXTRAPOLATOR_RESULT_DISEASES]
		if(!length(diseases))
			var/list/atom/targets = find_valid_targets(user, target)
			var/target_amt = length(targets)
			if(target_amt > 1)
				om_prompt(src, user, list("kind" = "list", "message" = "Select object to analyze", "title" = "Viral Extrapolation", "choices" = targets, "default" = targets[1], "requires" = PROMPT_HELD), PROC_REF(analyze_target_chosen))
				return
			target = target_amt ? targets[1] : null
		analyze_target_chosen(user, target)
	else
		to_chat(user, span_warning("The extrapolator has no scanner installed!"))

/obj/item/extrapolator/proc/analyze_target_chosen(mob/user, atom/target, datum/om/prompt/ask)
	var/list/result = target?.extrapolator_act(user, src, dry_run = TRUE)
	var/list/diseases = result && result[EXTRAPOLATOR_RESULT_DISEASES]
	if(!target)
		return
	if(!length(diseases))
		if(scan)
			to_chat(user, span_notice("[icon2html(src, user)] \The [src] fails to return any data."))
		else
			to_chat(user, span_notice("[icon2html(src, user)] \The [src]'s probe detects no diseases."))
		return
	if(EXTRAPOLATOR_ACT_CHECK(result, EXTRAPOLATOR_ACT_PRIORITY_SPECIAL))
		// extrapolator_act did some sort of special behavior, we don't need to do anything further
		return
	if(scan)
		scan(user, target)
	else
		extrapolate(user, target)

/obj/item/extrapolator/proc/find_valid_targets(mob/living/user, atom/target)
	. = list()
	var/turf/target_turf = get_turf(target)
	if(!target_turf)
		return
	for(var/atom/target_to_try in target_turf.contents - target)
		var/list/result = target_to_try.extrapolator_act(user, src, dry_run = TRUE)
		if(length(result[EXTRAPOLATOR_RESULT_DISEASES]))
			. += target_to_try

/obj/item/extrapolator/proc/scan(mob/living/user, atom/target)
	. = TRUE
	var/list/result = target?.extrapolator_act(user, target)
	var/list/diseases = result[EXTRAPOLATOR_RESULT_DISEASES]
	if(!length(diseases))
		return FALSE
	if(EXTRAPOLATOR_ACT_CHECK(result, EXTRAPOLATOR_ACT_PRIORITY_SPECIAL))
		return
	var/list/message = list()
	if(length(diseases))
		message += span_boldnotice("[costly_icon2html(target, user)] [target] scan results")
		message += span_boldnotice("[icon2html(src, user)] \The [src] detects the following diseases:")
		for(var/datum/affliction/contagion/disease in diseases)
			if(istype(disease, /datum/affliction/contagion/engineered))
				var/datum/affliction/contagion/engineered/advance_disease = disease
				var/list/properties
				if(global_flag_check(advance_disease.virus_modifiers, CARRIER))
					LAZYADD(properties, "carrier")
				if(global_flag_check(advance_disease.virus_modifiers, FALTERED))
					LAZYADD(properties, "faltered")
				message += span_info("<b>[advance_disease.name]</b>[LAZYLEN(properties) ? " ([properties.Join(", ")])" : ""], [global_flag_check(advance_disease.virus_modifiers, DORMANT) ? "<i>dormant virus</i>" : "stage [advance_disease.stage]/5"]")
				if(LAZYACCESS(extracted_ids, advance_disease.GetDiseaseID()))
					message += "This virus has been extracted by \the [src] previously."
				message += "[advance_disease.name] has the following symptoms:"
				for(var/datum/viral_trait/symptom in advance_disease.symptoms)
					message += "[symptom.name]"
			else
				message += span_info("<b>[disease.name]</b>, [global_flag_check(disease.virus_modifiers, DORMANT) ? "<i>dormant virus</i>" : "stage [disease.stage]/[disease.max_stages]"].")

			disease.addToDB()

	to_chat(user, examine_block(jointext(message, "\n")), avoid_highlighting = TRUE, trailing_newline = FALSE, type = MESSAGE_TYPE_INFO)

/obj/item/extrapolator/proc/extrapolate(mob/living/user, atom/target, isolate = FALSE)
	. = FALSE
	var/list/result = target?.extrapolator_act(user, target)
	var/list/diseases = result[EXTRAPOLATOR_RESULT_DISEASES]
	if(!length(diseases))
		return
	if(EXTRAPOLATOR_ACT_CHECK(result, EXTRAPOLATOR_ACT_PRIORITY_SPECIAL)) // hardcoded "we handled this ourselves" response
		return TRUE
	if(EXTRAPOLATOR_ACT_CHECK(result, EXTRAPOLATOR_ACT_PRIORITY_ISOLATE))
		isolate = TRUE
	//var/list/advance_diseases = list()
	if(!length(diseases))
		to_chat(user, span_warning("[icon2html(src, user)] There are no valid diseases to make a culture from."))
		return
	om_prompt_sequence(src, user, list(
		length(diseases) > 1 ? list("key" = "disease", "kind" = "list", "message" = "Select disease to extract", "title" = "Viral Extraction", "choices" = diseases, "default" = diseases[1]) : null,
		list("key" = "what", "message" = "What would you like to isolate?", "title" = "Isolate", "choices" = list("Symptom", "Disease")),
	), PROC_REF(isolation_chosen), list("requires" = PROMPT_HELD, "data" = list("target" = target, "disease" = diseases[1])))
	return TRUE

/obj/item/extrapolator/proc/isolation_chosen(mob/living/user, datum/om/prompt/ask)
	var/atom/target = ask.get("target")
	var/datum/affliction/contagion/engineered/target_disease = ask.get("disease")
	if(ask.get("what") == "Symptom")
		isolate_symptom(user, target, target_disease)
	else
		isolate_disease(user, target, target_disease)

/obj/item/extrapolator/proc/isolate_symptom(mob/living/user, atom/target, datum/affliction/contagion/engineered/target_disease)
	. = FALSE
	var/list/symptoms = list()
	for(var/datum/viral_trait/symptom in target_disease.symptoms)
		if(symptom.level <= maximum_level)
			symptoms += symptom
			continue
	if(!length(symptoms))
		to_chat(user, span_warning("[icon2html(src, user)] There are no symptoms that could be isolated.."))
		return
	if(length(symptoms) > 1)
		om_prompt(src, user, list("kind" = "list", "message" = "Select symptom to isolate", "title" = "Symptom Extraction", "choices" = symptoms, "default" = symptoms[1], "requires" = PROMPT_HELD, "data" = list("target" = target)), PROC_REF(symptom_chosen))
		return TRUE
	return symptom_chosen(user, symptoms[1], null, target)

/obj/item/extrapolator/proc/symptom_chosen(mob/living/user, datum/viral_trait/chosen, datum/om/prompt/ask, atom/target)
	if(ask)
		target = ask.get("target")
	user.visible_message(span_notice("[user] slots [target] into [src], which begins to whir and beep!"), span_notice("[icon2html(src, user)] You begin isolating " + span_bold("[chosen.name]") + " from [target]..."),)
	var/datum/affliction/contagion/engineered/symptom_holder = new
	symptom_holder.name = chosen.name
	symptom_holder.symptoms += chosen
	symptom_holder.Finalize()
	symptom_holder.Refresh()
	om_task_start(/datum/om/task/timed/extrapolator_isolate_symptom, user, target, list("receiver" = src, "duration" = extract_time, "symptom_holder" = symptom_holder))
	return TRUE

/datum/om/task/timed/extrapolator_isolate_symptom
	complete_proc = /obj/item/extrapolator/proc/isolate_symptom_timed_done
	var/datum/affliction/contagion/engineered/symptom_holder

/obj/item/extrapolator/proc/isolate_symptom_timed_done(datum/om/task/timed/extrapolator_isolate_symptom/task)
	var/mob/living/user = task.actor
	var/atom/target = task.target
	var/datum/affliction/contagion/engineered/symptom_holder = task.symptom_holder
	create_culture(user, symptom_holder, target)
	return TRUE

/obj/item/extrapolator/proc/isolate_disease(mob/living/user, atom/target, datum/affliction/contagion/engineered/target_disease, timer = 10 SECONDS)
	. = FALSE
	user.visible_message(span_notice("[user] begins to thoroughly scan [target] with [src]..."), \
		span_notice("[icon2html(src, user)] You begin isolating " + span_bold("[target_disease.name]") + " from [target]..."))
	om_task_start(/datum/om/task/timed/extrapolator_isolate_disease, user, target, list("receiver" = src, "duration" = isolate_time, "target_disease" = target_disease))
	return TRUE

/datum/om/task/timed/extrapolator_isolate_disease
	complete_proc = /obj/item/extrapolator/proc/isolate_disease_timed_done
	var/datum/affliction/contagion/engineered/target_disease

/obj/item/extrapolator/proc/isolate_disease_timed_done(datum/om/task/timed/extrapolator_isolate_disease/task)
	var/mob/living/user = task.actor
	var/atom/target = task.target
	var/datum/affliction/contagion/engineered/target_disease = task.target_disease
	create_culture(user, target_disease, target)
	return TRUE

/obj/item/extrapolator/proc/create_culture(mob/living/user, datum/affliction/contagion/engineered/disease)
	. = FALSE
	disease = disease.Copy()
	disease.virus_modifiers &= ~DORMANT
	var/list/data = list("viruses" = list(disease))
	if(user.get_active_hand() != src)
		to_chat(user, span_warning("The extrapolator must be held in your active hand to work!"))
		return
	var/obj/item/reagent_containers/glass/beaker/vial/culture_bottle = new(user.drop_location())
	culture_bottle.name = "[disease.name] culture bottle"
	culture_bottle.desc = "A small bottle. Contains [disease.agent] culture in synthblood medium."
	culture_bottle.reagents.add_reagent(REAGENT_ID_BLOOD, 5, data)
	user.put_in_hands(culture_bottle)
	playsound(src, 'sound/machines/ping.ogg', vol = 30, vary = TRUE)
	COOLDOWN_START(src, usage_cooldown, 1 SECONDS)
	LAZYSET(extracted_ids, disease.GetDiseaseID(), TRUE)
	return TRUE

/obj/item/extrapolator/tier5
	default_scanning_module = /obj/item/stock_parts/scanning_module

REF_HELD(/obj/item/extrapolator, list("scanner"))
