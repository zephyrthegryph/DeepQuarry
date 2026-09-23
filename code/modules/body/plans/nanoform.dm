// Nanoform body plan: a protean's nanite swarm. See doc/mob_life_architecture.md §6.2.
//
// - Every part, and the whole body, is BIOLOGY_NANOFORM: repair mechanisms and
//   biological mechanisms both reach it, and nothing claims it is organic.
// - Regeneration is a TREAT_REGENERATION treatment funded by refactory steel,
//   charged from what mend() actually repaired.
// - A body that would die instead goes dormant: the core_dormancy affliction
//   holds it alive through COMSIG_LIVING_BODY_STATUS until it is revived by
//   calibration, plating repair and defibrillation.

/datum/body/humanoid/nanoform

/datum/body/humanoid/nanoform/biology_of(location)
	return BIOLOGY_NANOFORM

/// Regeneration is plating and wiring repair; it never revives dead organs or
/// closes lesions that need surgery (bug 11).
/datum/body/humanoid/nanoform/mend(tag, amount, zone = null)
	if(tag != TREAT_REGENERATION)
		return ..()
	. = mend(TREAT_PLATING_REPAIR, amount / 2, zone)
	. += mend(TREAT_WIRING_REPAIR, amount / 2, zone)
	. += ..() // afflictions that answer to regeneration itself

/// Nanite repair is funded by the refactory (regenerate()), not natural regeneration.
/datum/body/humanoid/nanoform/regeneration_level()
	return 0

/datum/body/humanoid/nanoform/restore()
	..()
	regrow_structure()

/datum/body/humanoid/nanoform/life_tick()
	regenerate()
	return ..()

/// A body that would die goes dormant instead, on both the tick path
/// (evaluate_status) and the immediate path after an injury (check_death).
/datum/body/humanoid/nanoform/evaluate_status()
	go_dormant_if_dying()
	return ..()

/datum/body/humanoid/nanoform/check_death()
	go_dormant_if_dying()
	return ..()

/datum/body/humanoid/nanoform/proc/go_dormant_if_dying()
	if(owner.stat != DEAD && !(owner.status_flags & GODMODE) && !find_affliction(/datum/affliction/core_dormancy) && is_dead())
		afflict(/datum/affliction/core_dormancy)

/// Spend refactory steel on repair at the current form's regeneration rate.
/// Returns the points repaired.
/datum/body/humanoid/nanoform/proc/regenerate()
	var/mob/living/carbon/human/H = owner
	if(H.stat == DEAD || find_affliction(/datum/affliction/core_dormancy))
		return 0
	var/datum/form/F = H.current_form()
	if(!F || F.regeneration <= 0 || !is_injured())
		return 0
	var/obj/item/organ/internal/nano/refactory/R = H.nano_get_refactory()
	if(!R)
		return 0
	return R.fund_repair(H, list(TREAT_REGENERATION), F.regeneration)

/// Rebuild missing or stumped limbs and missing internal organs from the
/// species template. Used by a full heal and by revival.
/datum/body/humanoid/nanoform/proc/regrow_structure()
	var/mob/living/carbon/human/H = owner
	if(!H.species)
		return
	var/regrown = 0
	for(var/limb_tag in H.species.has_limbs)
		var/obj/item/organ/external/E = H.organs_by_name[limb_tag]
		if(E && !E.is_stump())
			continue
		if(E)
			E.removed()
			qdel(E)
		var/list/organ_data = H.species.has_limbs[limb_tag]
		var/limb_path = organ_data["path"]
		var/obj/item/organ/external/new_limb = new limb_path(H)
		new_limb.robotize(H.synthetic ? H.synthetic.company : null)
		new_limb.sync_colour_to_human(H)
		regrown++
	for(var/organ_tag in H.species.has_organ)
		if(H.internal_organs_by_name[organ_tag])
			continue
		var/organ_type = H.species.has_organ[organ_tag]
		H.internal_organs_by_name[organ_tag] = new organ_type(H, TRUE)
		regrown++
	if(regrown)
		H.regenerate_icons()
		log_game("NANOFORM: [key_name(H)] regrew [regrown] part(s).")
	return regrown


// --- Core dormancy ---------------------------------------------------------------------

/// A nanoform body that lost cohesion retreats into its core. It neither dies
/// nor acts; it is revived step by step by treatment mechanisms.
/datum/affliction/core_dormancy
	name = "core dormancy"
	category = "Synthetic"
	clinical_description = "The nanite swarm has lost cohesion and retreated into its control core. The core must be opened, recalibrated with a reboot programmer, rebuilt with nanopaste and jump-started with a defibrillator."
	biology = BIOLOGY_NANOFORM
	body_plans = BODY_PLAN_HUMANOID
	progression_rate = 0
	min_symptoms = 0
	max_symptoms = 0
	treated_by = list(TREAT_CALIBRATION = 1, TREAT_PLATING_REPAIR = 1, TREAT_DEFIBRILLATION = 1)
	/// DORMANCY_* revival step.
	var/revival_step = DORMANCY_SEALED
	/// The mob whose COMSIG_LIVING_BODY_STATUS we answer.
	var/mob/living/held_mob

/datum/affliction/core_dormancy/on_added()
	..()
	set_severity(AFFLICTION_SEVERITY_TERMINAL)
	held_mob = owner
	RegisterSignal(held_mob, COMSIG_LIVING_BODY_STATUS, PROC_REF(hold_alive))
	held_mob.Paralyse(3)
	log_game("NANOFORM: [key_name(held_mob)] entered core dormancy at [AREACOORD(held_mob)].")
	playsound(held_mob, 'sound/voice/borg_deathsound.ogg', 50, 1)
	held_mob.visible_message(span_bold("[held_mob.name]") + " shudders and retreats inwards, coalescing into a single core component!")
	to_chat(held_mob, span_warning("Your swarm has lost cohesion! You are locked in your core control module until you are repaired. Instructions for your revival are shown when your module is examined."))
	if(ishuman(held_mob))
		var/mob/living/carbon/human/H = held_mob
		var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
		F?.enter_rig()

/datum/affliction/core_dormancy/on_removed()
	release()
	return ..()

/datum/affliction/core_dormancy/Destroy()
	release()
	return ..()

/datum/affliction/core_dormancy/proc/release()
	if(!held_mob)
		return
	UnregisterSignal(held_mob, COMSIG_LIVING_BODY_STATUS)
	log_game("NANOFORM: [key_name(held_mob)] left core dormancy.")
	held_mob = null

/datum/affliction/core_dormancy/proc/hold_alive(mob/living/source)
	SIGNAL_HANDLER
	return COMPONENT_BODY_KEEP_ALIVE

/// Dormant cores don't progress or heal on their own; they stay down.
/datum/affliction/core_dormancy/tick()
	owner?.Paralyse(3)

/datum/affliction/core_dormancy/proc/open_panel()
	if(revival_step == DORMANCY_SEALED)
		revival_step = DORMANCY_OPEN

/// Each revival mechanism advances exactly one step, in order.
/datum/affliction/core_dormancy/receive_tagged_treatment(tag, amount, continuous = FALSE)
	var/next_step
	switch(revival_step)
		if(DORMANCY_OPEN)
			if(tag == TREAT_CALIBRATION)
				next_step = DORMANCY_PROGRAMMED
		if(DORMANCY_PROGRAMMED)
			if(tag == TREAT_PLATING_REPAIR)
				next_step = DORMANCY_PASTED
		if(DORMANCY_PASTED)
			if(tag == TREAT_DEFIBRILLATION)
				next_step = DORMANCY_REBOOTING
	if(!next_step)
		return 0
	revival_step = next_step
	log_game("NANOFORM: [key_name(owner)] dormancy advanced to step [revival_step] by [tag].")
	if(revival_step == DORMANCY_REBOOTING)
		addtimer(CALLBACK(src, PROC_REF(complete_revival)), DORMANCY_REBOOT_TIME, TIMER_STOPPABLE)
	return 1

/// Reassembly finished: rebuild the body. The full heal cures this affliction.
/datum/affliction/core_dormancy/proc/complete_revival()
	var/mob/living/patient = owner
	if(!patient)
		return
	log_game("NANOFORM: [key_name(patient)] reconstituted from core dormancy.")
	patient.fully_heal()
	patient.SetParalysis(0)
	to_chat(patient, span_notice("You have finished reconstituting."))
	playsound(get_turf(patient), 'sound/machines/ding.ogg', 50, 1)

/datum/affliction/core_dormancy/proc/revival_instructions()
	switch(revival_step)
		if(DORMANCY_SEALED)
			return "Use a screwdriver to start repairs."
		if(DORMANCY_OPEN)
			return "Insert a Protean Reboot Programmer, printed from a protolathe."
		if(DORMANCY_PROGRAMMED)
			return "Use some Nanopaste."
		if(DORMANCY_PASTED)
			return "Use either a defib or jumper cables to start the reboot sequence."
		if(DORMANCY_REBOOTING)
			return "Reassembly in progress."
