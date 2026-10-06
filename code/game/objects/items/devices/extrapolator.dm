/obj/item/extrapolator
	name = "virus extrapolator"
	icon = 'icons/obj/device.dmi'
	icon_state = "extrapolator_scan"
	desc = "A bulky scanning device, used to extract genetic material of potential pathogens."
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

/// The scanning module the extrapolator is made with (its constructor param): a part or its type.
/obj/item/extrapolator/var/tmp/scanner_at_make

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/extrapolator/proc/fit_scanner(starting_scanner)
	starting_scanner = starting_scanner || default_scanning_module
	if(ispath(starting_scanner, /obj/item/stock_parts/scanning_module))
		rel_set(src, nameof(scanner), new starting_scanner(src))
	else if(istype(starting_scanner, /obj/item/stock_parts/scanning_module))
		move_into(src, nameof(src.scanner), starting_scanner)
	refresh_parts()

CAPABILITIES(/obj/item/extrapolator)
	op("mode", in_hand(), label("Toggle extrapolator mode"), then(PROC_REF(extrapolator_mode_selected)))
	op("item", item(/obj/item/stock_parts/scanning_module), label("Install"), then(PROC_REF(interaction_item)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(0), then(PROC_REF(screwdriver_used)))
	param(nameof(scanner_at_make), pos = 1, apply = PROC_REF(fit_scanner), keep = FALSE)

/obj/item/extrapolator/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/item = A.held
	if(!scanner)
		if(!move_into(src, nameof(src.scanner), item, user))
			return TRUE
		to_chat(user, span_notice("You install \the [scanner] in [src]."))
		refresh_parts()
	else
		to_chat(user, span_notice("[src] already has \the [scanner] installed."))
	return TRUE

/obj/item/extrapolator/proc/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!scanner)
		to_chat(user, span_warning("\The [src] has no scanner to remove!"))
		return OP_OK
	to_chat(user, span_notice("You remove \the [scanner] from \the [src]."))
	scanner.forceMove(drop_location())
	rel_take(src, nameof(scanner))
	playsound(src, tool.usesound, 50, 1)
	return OP_OK

/obj/item/extrapolator/proc/extrapolator_mode_selected(datum/act/op/A)
	var/mob/user = A.actor
	play_sfx(src, SFX_MACHINES_CLICK)
	if(scan)
		icon_state = "extrapolator_sample"
		scan = FALSE
		to_chat(user, span_notice("You remove the probe from the device and set it to EXTRACT."))
	else
		icon_state = "extrapolator_scan"
		scan = TRUE
		to_chat(user, span_notice("You put the probe back into the device and set it to SCAN."))
	return OP_OK

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
				open_request(src, /datum/prompt/choice/viral_extrapolator/analyze_target, PROC_REF(analyze_target_answered), answerer = user, choices = targets, default = targets[1])
				return
			target = target_amt ? targets[1] : null
		analyze_target_chosen(user, target)
	else
		to_chat(user, span_warning("The extrapolator has no scanner installed!"))

/// Extrapolator prompts retain the carried/capable answer checks.
/datum/prompt/choice/viral_extrapolator
	ask_flags = ASK_CARRIED | ASK_CAPABLE
	timeout = 0
	var/atom/extraction_target
	var/datum/affliction/contagion/extraction_disease
	var/target_expected = FALSE
	var/disease_expected = FALSE

CAPABILITIES(/datum/prompt/choice/viral_extrapolator)
	ref_one(nameof(extraction_target), /atom)
	ref_one(nameof(extraction_disease), /datum/affliction/contagion)

/datum/prompt/choice/viral_extrapolator/prepare(datum/act/A)
	. = ..()
	var/atom/target = extraction_target
	var/datum/affliction/contagion/disease = extraction_disease
	rel_clear(src, nameof(extraction_target))
	rel_clear(src, nameof(extraction_disease))
	rel_set(src, nameof(extraction_target), target)
	rel_set(src, nameof(extraction_disease), disease)

/datum/prompt/choice/viral_extrapolator/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(answerer) || (target_expected && QDELETED(extraction_target)) || (disease_expected && QDELETED(extraction_disease)))
		return "gone"
	if(isdatum(value))
		var/datum/selected = value
		if(QDELETED(selected))
			return "gone"
	return null

/datum/prompt/choice/viral_extrapolator/analyze_target
	title = "Viral Extrapolation"
	question = "Select object to analyze"

/datum/prompt/choice/viral_extrapolator/disease
	title = "Viral Extraction"
	question = "Select disease to extract"

/datum/prompt/choice/viral_extrapolator/isolate_what
	title = "Isolate"
	question = "What would you like to isolate?"
	choices = list("Symptom", "Disease")
	buttons = TRUE

/datum/prompt/choice/viral_extrapolator/symptom
	title = "Symptom Extraction"
	question = "Select symptom to isolate"

/obj/item/extrapolator/proc/analyze_target_answered(datum/act/request/A)
	if(!A.answer)
		return
	return apply_analyze_target_answered(A)

/obj/item/extrapolator/proc/apply_analyze_target_answered(datum/act/request/A)
	var/datum/prompt/choice/viral_extrapolator/analyze_target/ask = A.request
	analyze_target_chosen(ask.answerer, A.answer.value)

/obj/item/extrapolator/proc/analyze_target_chosen(mob/user, atom/target)
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
	for(var/atom/target_to_try in contents_of(target_turf) - target)
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
	if(!length(diseases))
		to_chat(user, span_warning("[icon2html(src, user)] There are no valid diseases to make a culture from."))
		return
	if(length(diseases) > 1)
		open_request(src, /datum/prompt/choice/viral_extrapolator/disease, PROC_REF(disease_chosen), answerer = user, choices = diseases, default = diseases[1], extraction_target = target, target_expected = !isnull(target))
	else
		open_request(src, /datum/prompt/choice/viral_extrapolator/isolate_what, PROC_REF(isolation_chosen), answerer = user, extraction_target = target, target_expected = !isnull(target), extraction_disease = diseases[1], disease_expected = !isnull(diseases[1]))
	return TRUE

/obj/item/extrapolator/proc/disease_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return apply_disease_chosen(A)

/obj/item/extrapolator/proc/apply_disease_chosen(datum/act/request/A)
	var/datum/prompt/choice/viral_extrapolator/disease/ask = A.request
	open_request(src, /datum/prompt/choice/viral_extrapolator/isolate_what, PROC_REF(isolation_chosen), answerer = ask.answerer, extraction_target = ask.extraction_target, target_expected = !isnull(ask.extraction_target), extraction_disease = A.answer.value, disease_expected = !isnull(A.answer.value))

/obj/item/extrapolator/proc/isolation_chosen(datum/act/request/A)
	if(!A.answer)
		return
	return apply_isolation_chosen(A)

/obj/item/extrapolator/proc/apply_isolation_chosen(datum/act/request/A)
	var/datum/prompt/choice/viral_extrapolator/isolate_what/ask = A.request
	var/mob/living/user = ask.answerer
	var/atom/target = ask.extraction_target
	var/datum/affliction/contagion/engineered/target_disease = ask.extraction_disease
	if(A.answer.value == "Symptom")
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
		open_request(src, /datum/prompt/choice/viral_extrapolator/symptom, PROC_REF(symptom_answered), answerer = user, choices = symptoms, default = symptoms[1], extraction_target = target, target_expected = !isnull(target))
		return TRUE
	return symptom_chosen(user, symptoms[1], target)

/obj/item/extrapolator/proc/symptom_answered(datum/act/request/A)
	if(!A.answer)
		return
	return apply_symptom_answered(A)

/obj/item/extrapolator/proc/apply_symptom_answered(datum/act/request/A)
	var/datum/prompt/choice/viral_extrapolator/symptom/ask = A.request
	symptom_chosen(ask.answerer, A.answer.value, ask.extraction_target)

/obj/item/extrapolator/proc/symptom_chosen(mob/living/user, datum/viral_trait/chosen, atom/target)
	act_message(user, src, MSG_SELF(span_notice("[icon2html(src, user)] You begin isolating " + span_bold("[chosen.name]") + " from [target]...")), MSG_OTHERS(span_notice("%U% slots [target] into %T%, which begins to whir and beep!")))
	var/datum/affliction/contagion/engineered/symptom_holder = new
	symptom_holder.name = chosen.name
	rel_add(symptom_holder, nameof(symptom_holder.symptoms), chosen.Copy()) // the target disease owns `chosen`; the isolate gets its own copy
	symptom_holder.Finalize()
	symptom_holder.Refresh()
	om_task_start(/datum/om/task/timed/extrapolator_isolate_symptom, user, target, receiver = src, duration = extract_time, symptom_holder = symptom_holder)
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
	act_message(user, src, MSG_SELF(span_notice("[icon2html(src, user)] You begin isolating " + span_bold("[target_disease.name]") + " from [target]...")), \
		MSG_OTHERS(span_notice("%U% begins to thoroughly scan [target] with %T%...")))
	om_task_start(/datum/om/task/timed/extrapolator_isolate_disease, user, target, receiver = src, duration = isolate_time, target_disease = target_disease)
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
	disease.set_virus_modifiers(disease.virus_modifiers & ~DORMANT)
	var/list/data = list("viruses" = list(disease))
	if(user.get_active_hand() != src)
		to_chat(user, span_warning("The extrapolator must be held in your active hand to work!"))
		return
	var/obj/item/reagent_containers/glass/beaker/vial/culture_bottle = new(user.drop_location())
	culture_bottle.name = "[disease.name] culture bottle"
	culture_bottle.desc = "A small bottle. Contains [disease.agent] culture in synthblood medium."
	culture_bottle.reagents.add_reagent(REAGENT_ID_BLOOD, 5, data)
	user.put_in_hands(culture_bottle)
	play_sfx(src, SFX_MACHINES_PING, 0.6, vary = TRUE)
	COOLDOWN_START(src, usage_cooldown, 1 SECONDS)
	LAZYSET(extracted_ids, disease.GetDiseaseID(), TRUE)
	return TRUE

/obj/item/extrapolator/tier5
	default_scanning_module = /obj/item/stock_parts/scanning_module

/obj/item/extrapolator/ownership()
	. = ..()
	. += owns(nameof(scanner), policy = OWN_CONTAINED)
