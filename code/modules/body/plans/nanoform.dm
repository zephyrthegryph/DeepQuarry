// Nanoform body plan: a protean's nanite swarm. See doc/mob_life_architecture.md §6.2.
//
// - Every part, and the whole body, is BIOLOGY_NANOFORM. Only the nanite
//   mechanisms reach it: plating, wiring and calibration repair, its own
//   regeneration and refactory feedstock (treatment_tag_biology()).
// - Regeneration is a TREAT_REGENERATION treatment funded by refactory steel,
//   charged from what mend() actually repaired, scaled by BF_HEALING.
// - The swarm's own troubles are nanite afflictions
//   (code/modules/medical/conditions/nanite.dm); this plan triggers them.
// - A body that would die instead goes dormant: the core_dormancy affliction
//   holds it alive through COMSIG_LIVING_BODY_STATUS, knocks it out through
//   the consciousness model and leaves its control cluster inert, until it is
//   revived by calibration, plating repair and defibrillation.

/datum/body/humanoid/nanoform

/datum/body/humanoid/nanoform/biology_of(location)
	return BIOLOGY_NANOFORM

/// Regeneration is plating and wiring repair; it never revives dead organs or
/// closes lesions that need surgery (bug 11).
/datum/body/humanoid/nanoform/mend(tag, amount, target = null)
	if(tag != TREAT_REGENERATION)
		return ..()
	. = mend(TREAT_PLATING_REPAIR, amount / 2, target)
	. += mend(TREAT_WIRING_REPAIR, amount / 2, target)
	. += ..() // afflictions that answer to regeneration itself

/// Nanite repair is funded by the refactory (regenerate()), not natural regeneration.
/datum/body/humanoid/nanoform/regeneration_level()
	return 0

/datum/body/humanoid/nanoform/restore()
	..()
	regrow_structure()

/datum/body/humanoid/nanoform/life_tick()
	regenerate()
	state_triggers()
	return ..()

/datum/body/humanoid/nanoform/receive_injury(kind, amount, target, atom/source, affliction_type, flags)
	. = ..()
	if(. > 0)
		injury_triggers(kind, ., target)

/// A body that would die goes dormant instead, on both the tick path
/// (evaluate_status) and the immediate path after an injury (check_death).
/// This holds whether the swarm collapsed on the floor or had folded itself
/// into its control cluster.
/datum/body/humanoid/nanoform/evaluate_status()
	go_dormant_if_dying()
	return ..()

/datum/body/humanoid/nanoform/check_death()
	go_dormant_if_dying()
	return ..()

/// A dormant core is held alive but is not awake: dormancy's consciousness
/// penalty applies even though the keep-alive answers the status signal.
/datum/body/humanoid/nanoform/is_unconscious()
	if(!is_dormant() || (owner.status_flags & GODMODE))
		return ..()
	ensure_vitals()
	return consciousness <= CONSCIOUSNESS_THRESHOLD

/datum/body/humanoid/nanoform/proc/is_dormant()
	return has_affliction(/datum/affliction/core_dormancy)

/datum/body/humanoid/nanoform/proc/go_dormant_if_dying()
	if(owner.stat == DEAD || (owner.status_flags & GODMODE) || is_dormant() || !is_dead())
		return
	log_game("NANOFORM: [key_name(owner)] took lethal damage[istype(owner.loc, /obj/item/rig/protean) ? " while folded into their control cluster" : ""]; going dormant.")
	afflict(/datum/affliction/core_dormancy)

/// Spend refactory steel on repair at the current form's regeneration rate.
/// A swarm that needs repair and has no steel starts depleting its
/// refactory. Returns the points repaired.
/datum/body/humanoid/nanoform/proc/regenerate()
	var/mob/living/carbon/human/H = owner
	if(H.stat == DEAD || is_dormant())
		return 0
	var/datum/form/F = H.current_form()
	if(!F || F.regeneration <= 0 || !is_injured())
		return 0
	var/obj/item/organ/internal/nano/refactory/R = H.nano_get_refactory()
	if(!R)
		return 0
	if(R.get_stored_material(MAT_STEEL) < NANOFORM_STEEL_PER_POINT)
		afflict(/datum/affliction/nanite/refactory_depletion, R, NANITE_DEPLETION_PER_STARVED_TICK)
		return 0
	return R.fund_repair(H, list(TREAT_REGENERATION), F.regeneration * get_factor(BF_HEALING))

/// Hits that land shake the swarm's cohesion; hits on the orchestrator, and
/// shocks anywhere, damage its control.
/datum/body/humanoid/nanoform/proc/injury_triggers(kind, amount, target)
	var/category = injury_category(kind)
	if((category == INJURY_CATEGORY_PHYSICAL || category == INJURY_CATEGORY_THERMAL) && amount >= NANITE_COHESION_MIN_HIT)
		afflict(/datum/affliction/nanite/cohesion_loss, null, amount * NANITE_COHESION_PER_POINT)
	var/mob/living/carbon/human/H = owner
	var/obj/item/organ/internal/nano/orchestrator/O = H.internal_organs_by_name?[O_ORCH]
	if(!istype(O))
		return
	var/control_damage = 0
	if(resolve_zone(target) == O)
		control_damage += amount * NANITE_ORCHESTRATOR_PER_POINT
	if(kind == INJURY_ELECTRIC)
		control_damage += amount * NANITE_ORCHESTRATOR_PER_SHOCK
	if(control_damage > 0)
		afflict(/datum/affliction/nanite/orchestrator_damage, O, control_damage)

/// Per-tick state the swarm reacts to: foreign reagents contaminate it.
/datum/body/humanoid/nanoform/proc/state_triggers()
	if(owner.stat == DEAD)
		return
	var/foreign = foreign_reagent_volume()
	if(foreign <= 0)
		return
	var/mob/living/carbon/human/H = owner
	afflict(/datum/affliction/nanite/contamination, H.nano_get_refactory(), min(foreign * NANITE_CONTAMINATION_PER_UNIT, NANITE_CONTAMINATION_MAX_PER_TICK))

/// Units of reagent in the swarm that aren't nanite material.
/datum/body/humanoid/nanoform/proc/foreign_reagent_volume()
	var/static/list/nanite_reagents = list(REAGENT_ID_LIQUIDPROTEAN = TRUE, REAGENT_ID_HEALINGNANITES = TRUE)
	if(dirty & BODY_DIRTY_TREATMENT)
		build_treatment_snapshot()
	. = 0
	for(var/reagent_id in reagent_volumes)
		if(!nanite_reagents[reagent_id])
			. += reagent_volumes[reagent_id]

/// Revival from dormancy: rebuild what the revival steps repaired. The
/// missing structure regrows, nanopaste has rebuilt the vital parts' plating
/// and wiring, the reboot programmer has recalibrated the orchestrator, and
/// the swarm's cohesion is whole again. Everything else stays.
/datum/body/humanoid/nanoform/proc/rebuild_cohesion()
	var/mob/living/carbon/human/H = owner
	regrow_structure()
	for(var/obj/item/organ/external/E as anything in H.organs)
		if(!E.vital)
			continue
		mend(TREAT_PLATING_REPAIR, E.get_trauma() + E.get_burn(), E)
		mend(TREAT_WIRING_REPAIR, E.get_trauma() + E.get_burn(), E)
	var/obj/item/organ/internal/nano/orchestrator/O = H.internal_organs_by_name?[O_ORCH]
	if(istype(O))
		mend(TREAT_CALIBRATION, AFFLICTION_SEVERITY_TERMINAL, O)
	var/datum/affliction/cohesion = find_affliction(/datum/affliction/nanite/cohesion_loss)
	cohesion?.cure()
	log_game("NANOFORM: [key_name(H)] rebuilt cohesion; [LAZYLEN(afflictions)] affliction(s) remain.")

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
/// nor acts: it is held alive (COMSIG_LIVING_BODY_STATUS) and unconscious
/// (consciousness_at_max), its control cluster goes inert, and it is revived
/// step by step by treatment mechanisms.
/datum/affliction/core_dormancy
	name = "core dormancy"
	category = "Synthetic"
	clinical_description = "The nanite swarm has lost cohesion and retreated into its control core. The core must be opened, recalibrated with a reboot programmer, rebuilt with nanopaste and jump-started with a defibrillator."
	biology = BIOLOGY_NANOFORM
	body_plans = BODY_PLAN_HUMANOID
	progression_rate = 0
	min_symptoms = 0
	max_symptoms = 0
	/// At terminal severity the core is far below the consciousness threshold.
	consciousness_at_max = 200
	treated_by = list(TREAT_CALIBRATION = 1, TREAT_PLATING_REPAIR = 1, TREAT_DEFIBRILLATION = 1)
	/// DORMANCY_* revival step.
	var/revival_step = DORMANCY_SEALED
	/// The mob whose COMSIG_LIVING_BODY_STATUS we answer.
	var/mob/living/held_mob
	/// The reboot timer, once the core is jump-started.
	var/reboot_timer

/datum/affliction/core_dormancy/on_added()
	..()
	set_severity(AFFLICTION_SEVERITY_TERMINAL)
	held_mob = owner
	RegisterSignal(held_mob, COMSIG_LIVING_BODY_STATUS, PROC_REF(hold_alive))
	log_game("NANOFORM: [key_name(held_mob)] entered core dormancy at [AREACOORD(held_mob)].")
	playsound(held_mob, 'sound/voice/borg_deathsound.ogg', 50, 1)
	held_mob.visible_message(span_bold("[held_mob.name]") + " shudders and retreats inwards, coalescing into a single core component!")
	to_chat(held_mob, span_warning("Your swarm has lost cohesion! You are locked in your core control module until you are repaired. Instructions for your revival are shown when your module is examined."))
	var/datum/component/forms/protean/F = held_mob.GetComponent(/datum/component/forms/protean)
	if(!F)
		return
	F.enter_rig()
	F.rig?.go_inert()

/datum/affliction/core_dormancy/on_removed()
	release()
	return ..()

/datum/affliction/core_dormancy/Destroy()
	release()
	return ..()

/datum/affliction/core_dormancy/proc/release()
	if(reboot_timer)
		deltimer(reboot_timer)
		reboot_timer = null
	if(!held_mob)
		return
	UnregisterSignal(held_mob, COMSIG_LIVING_BODY_STATUS)
	var/datum/component/forms/protean/F = held_mob.GetComponent(/datum/component/forms/protean)
	F?.rig?.wake()
	log_game("NANOFORM: [key_name(held_mob)] left core dormancy.")
	held_mob = null

/datum/affliction/core_dormancy/proc/hold_alive(mob/living/source)
	SIGNAL_HANDLER
	return COMPONENT_BODY_KEEP_ALIVE

/// Dormant cores don't progress or heal on their own; they stay down.
/datum/affliction/core_dormancy/progress()
	pending_treatment = 0

/datum/affliction/core_dormancy/proc/open_panel()
	if(revival_step == DORMANCY_SEALED)
		revival_step = DORMANCY_OPEN

/// Each revival mechanism advances exactly one step, in order.
/datum/affliction/core_dormancy/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(continuous)
		return 0
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
		reboot_timer = addtimer(CALLBACK(src, PROC_REF(complete_revival)), DORMANCY_REBOOT_TIME, TIMER_STOPPABLE)
	return 1

/// Reassembly finished: rebuild cohesion and what the revival steps repaired,
/// then leave dormancy. Afflictions the revival didn't touch stay.
/datum/affliction/core_dormancy/proc/complete_revival()
	if(reboot_timer)
		deltimer(reboot_timer)
		reboot_timer = null
	var/mob/living/patient = owner
	var/datum/body/humanoid/nanoform/B = body
	if(!patient || !istype(B))
		return
	log_game("NANOFORM: [key_name(patient)] reconstituting from core dormancy.")
	B.rebuild_cohesion()
	cure()
	B.on_status_changed()
	if(B.is_dormant())
		log_game("NANOFORM: [key_name(patient)] was still lethally damaged after reconstitution and fell dormant again.")
		return
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
