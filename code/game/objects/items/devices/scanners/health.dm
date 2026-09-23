/// Past this long since death, resuscitation is no longer possible.
#define DEFIB_TIME_LIMIT (10 MINUTES)

// Handheld health analyzers. Each tier is a diagnostic profile: the analyzer
// diagnoses the patient through it and renders the report to chat. What a tier
// can see (surface signs only, internal imaging, lab tests) lives in the
// profile, not here. See code/modules/medical/diagnosis/.
/obj/item/healthanalyzer
	name = "health analyzer"
	desc = "A hand-held body scanner able to distinguish vital signs of the subject."
	icon = 'icons/obj/device.dmi'
	icon_state = "health"
	item_state = "healthanalyzer"
	slot_flags = SLOT_BELT
	throwforce = 3
	w_class = ITEMSIZE_SMALL
	throw_speed = 5
	throw_range = 10
	MATERIAL_BULK(MAT_STEEL, 200)
	/// The diagnostic profile this analyzer scans with.
	var/profile_type = /datum/diagnostic_profile/health_analyzer
	/// FALSE = scan with the basic profile only (hides advanced detail).
	var/showadvscan = TRUE
	var/guide = FALSE

	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/healthanalyzer/Initialize(mapload)
	. = ..()
	if(profile_type != /datum/diagnostic_profile/health_analyzer)
		verbs += /obj/item/healthanalyzer/proc/toggle_adv

/obj/item/healthanalyzer/examine(mob/user)
	. = ..()
	if(guide)
		. += span_notice("Guidance is currently enabled.")
	else
		. += span_notice("Guidance is currently disabled.")

/obj/item/healthanalyzer/do_surgery(mob/living/M, mob/living/user)
	if(user.a_intent != I_HELP) //in case it is ever used as a surgery tool
		return ..()
	scan_mob(M, user) //default surgery behaviour is just to scan as usual
	return 1

/obj/item/healthanalyzer/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	scan_mob(M, user)
	return ITEM_INTERACT_SUCCESS

/// The profile the next scan uses.
/obj/item/healthanalyzer/proc/active_profile()
	return showadvscan ? profile_type : /datum/diagnostic_profile/health_analyzer

/obj/item/healthanalyzer/proc/scan_mob(mob/living/M, mob/living/user)
	if(!user)
		return
	if(CLUMSY_FAIL_CHANCE(user))
		user.visible_message(span_warning("\The [user] has analyzed the floor's vitals!"), span_warning("You try to analyze the floor's vitals!"))
		to_chat(user, span_notice("Health analyzer results for the floor: no vital signs."))
		return
	if(!user.IsAdvancedToolUser())
		to_chat(user, span_warning("You don't have the dexterity to do this!"))
		return
	if(!istype(M))
		return

	flick("[icon_state]-scan", src)
	user.visible_message(span_notice("[user] has analyzed [M]'s vitals."), span_notice("You have analyzed [M]'s vitals."))

	var/datum/diagnosis/D = M.diagnose(active_profile())
	if(!D)
		return
	var/list/dat = list(D.render_chat())
	if(D.status == DIAG_STATUS_DEAD && D.time_of_death && (world.time - D.time_of_death) < DEFIB_TIME_LIMIT)
		dat += span_boldnotice("Subject died [DisplayTimeText(world.time - D.time_of_death)] ago - resuscitation may be possible!")
	dat += reagent_lines(M, D.profile.scan_level)
	dat += patient_notes(M, D.profile.scan_level)
	user.show_message(dat.Join("<br>"), 1)
	log_diagnosis(user, M, D)
	qdel(D)
	if(guide)
		guide(M, user)

/// Reagents the analyzer's tier can identify, per holder.
/obj/item/healthanalyzer/proc/reagent_lines(mob/living/M, scan_level)
	. = list()
	if(!iscarbon(M))
		return
	var/mob/living/carbon/C = M
	var/list/holders = list("blood" = C.reagents, "stomach" = C.ingested, "dermis" = C.touching)
	for(var/where in holders)
		var/datum/reagents/holder = holders[where]
		if(!holder?.total_volume)
			continue
		var/list/known = list()
		var/unknown = 0
		for(var/datum/reagent/R as anything in holder.reagent_list)
			if(scan_level < R.scannable)
				unknown++
				continue
			var/overdose = R.overdose && R.volume > R.overdose && (where != "dermis" || R.can_overdose_touch)
			known += "&emsp;[round(R.volume, 1)]u [R.name][overdose ? " - [span_danger("Overdose")]" : ""]"
		if(length(known))
			. += span_notice("Reagents detected in subject's [where]:<br>[known.Join("<br>")]")
		if(unknown)
			. += span_warning("Unknown substance[unknown > 1 ? "s" : ""] detected in subject's [where].")

/// Patient-specific notes outside the affliction model (genetics, addiction,
/// species biology, parasites).
/obj/item/healthanalyzer/proc/patient_notes(mob/living/M, scan_level)
	. = list()
	if(scan_level >= SCANNABLE_DIFFICULT && M.has_brain_worms())
		. += span_warning("Subject suffering from aberrant brain activity. Recommend further scanning.")
	if(!ishuman(M))
		return
	var/mob/living/carbon/human/H = M
	for(var/datum/genetics/side_effect/side_effect in H.genetic_side_effects)
		var/datum/reagent/Rd = SSchemistry.chemical_reagents[side_effect.antidote_reagent]
		. += span_danger("Patient is suffering from [side_effect.name]. [Rd ? "Treatment: [Rd]" : "There is no known treatment."]")
	if(H.get_addiction_to_reagent(REAGENT_ID_ASUSTENANCE) > 0)
		. += span_warning("Biologically unstable, requires [REAGENT_ASUSTENANCE] to function properly.")
	for(var/addic in H.get_all_addictions())
		var/level = H.get_addiction_to_reagent(addic)
		if(level <= 0 || addic == REAGENT_ID_ASUSTENANCE)
			continue
		if(scan_level < SCANNABLE_DIFFICULT && level > 120)
			continue
		var/datum/reagent/R = SSchemistry.chemical_reagents[addic]
		if(scan_level < SCANNABLE_ADVANCED)
			. += span_warning("Chemical dependance detected.")
			break
		if(scan_level >= SCANNABLE_DIFFICULT && level <= 80)
			. += span_warning("Experiencing withdrawls from [R.name], [REAGENT_INAPROVALINE] treatment recomended.")
		else
			. += span_warning("Chemical dependance detected: [R.name].")
	var/datum/component/xenochimera/xc = H.get_xenochimera_component()
	if(xc)
		if(H.stat == DEAD && xc.revive_ready == REVIVING_READY && !H.hasnutriment())
			. += span_danger("WARNING: Protein levels low. Subject incapable of reconstitution.")
		else if(xc.revive_ready == REVIVING_NOW)
			. += span_warning("Subject is undergoing form reconstruction. Estimated time to finish is in: [round((xc.revive_finished - world.time) / 10)] seconds.")
		else if(xc.revive_ready == REVIVING_DONE)
			. += span_notice("Subject is ready to hatch. Transfer to dark room for holding with food available.")
		else if(H.stat == DEAD)
			. += span_danger("WARNING: Defib will cause extreme pain and set subject feral. Sedation recommended prior to defibrillation.")
		else
			. += span_notice("Subject is a Xenochimera. Treat accordingly.")

/obj/item/healthanalyzer/proc/toggle_adv()
	set name = "Toggle Advanced Scan"
	set category = "Object"

	showadvscan = !showadvscan
	to_chat(usr, "The scanner will now perform [showadvscan ? "an advanced" : "a basic"] analysis.")

/obj/item/healthanalyzer/improved //reports localized injuries, blood pressure and more reagents
	name = "improved health analyzer"
	desc = "A miracle of medical technology, this handheld scanner can produce an accurate and specific report of a patient's biosigns."
	profile_type = /datum/diagnostic_profile/health_analyzer/improved
	icon_state = "health1"

/obj/item/healthanalyzer/advanced //adds internal imaging, full vitals and treatment hints
	name = "advanced health analyzer"
	desc = "An even more advanced handheld health scanner, complete with a full biosign monitor and on-board radiation and neurological analysis suites."
	profile_type = /datum/diagnostic_profile/health_analyzer/advanced
	icon_state = "health2"

/obj/item/healthanalyzer/phasic //adds laboratory-grade tests and trends
	name = "phasic health analyzer"
	desc = "Possibly the most advanced health analyzer to ever have existed, utilising bluespace technology to determine almost everything worth knowing about a patient."
	profile_type = /datum/diagnostic_profile/health_analyzer/phasic
	icon_state = "health3"

#undef DEFIB_TIME_LIMIT
