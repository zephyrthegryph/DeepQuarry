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
//   holds it alive through the /datum/act/body_status question it takes over, knocks it out through
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
	if(!is_dormant() || in_godmode(owner))
		return ..()
	ensure_vitals()
	return consciousness <= CONSCIOUSNESS_THRESHOLD

/datum/body/humanoid/nanoform/proc/is_dormant()
	return has_affliction(/datum/affliction/core_dormancy)

/datum/body/humanoid/nanoform/proc/go_dormant_if_dying()
	if(owner.is_dead() || in_godmode(owner) || is_dormant() || !is_lethal())
		return
	log_game("NANOFORM: [key_name(owner)] took lethal damage[istype(owner.loc, /obj/item/rig/protean) ? " while folded into their control cluster" : ""]; going dormant.")
	afflict(/datum/affliction/core_dormancy)

/// Spend refactory steel on repair at the current form's regeneration rate.
/// A swarm that needs repair and has no steel starts depleting its
/// refactory. Returns the points repaired.
/datum/body/humanoid/nanoform/proc/regenerate()
	var/mob/living/carbon/human/H = owner
	if(H.is_dead() || is_dormant())
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
	var/obj/item/organ/internal/nano/orchestrator/O = H.organ_in(O_ORCH)
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
	if(owner.is_dead())
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
	var/obj/item/organ/internal/nano/orchestrator/O = H.organ_in(O_ORCH)
	if(istype(O))
		mend(TREAT_CALIBRATION, AFFLICTION_SEVERITY_TERMINAL, O)
	var/datum/affliction/cohesion = find_affliction(/datum/affliction/nanite/cohesion_loss)
	cohesion?.cure()
	log_game("NANOFORM: [key_name(H)] rebuilt cohesion; [LAZYLEN(afflictions)] affliction(s) remain.")

/// Total Reassembly: the swarm rebuilds itself from `steel` of refactory
/// feedstock, already consumed by the caller. Missing structure regrows,
/// cohesion is whole again and the orchestrator recalibrates; the steel then
/// funds plating and wiring repair across the body at NANOFORM_STEEL_PER_POINT.
/// Like revival from dormancy, afflictions the repair doesn't reach stay.
/// Returns the points repaired.
/datum/body/humanoid/nanoform/proc/total_reassembly(steel)
	var/mob/living/carbon/human/H = owner
	regrow_structure()
	var/datum/affliction/cohesion = find_affliction(/datum/affliction/nanite/cohesion_loss)
	cohesion?.cure()
	var/obj/item/organ/internal/nano/orchestrator/O = H.organ_in(O_ORCH)
	if(istype(O))
		mend(TREAT_CALIBRATION, AFFLICTION_SEVERITY_TERMINAL, O)
	var/points = max(steel, 0) / NANOFORM_STEEL_PER_POINT
	. = mend(TREAT_PLATING_REPAIR, points / 2)
	. += mend(TREAT_WIRING_REPAIR, points / 2)
	on_status_changed()
	log_game("NANOFORM: [key_name(H)] total reassembly spent [steel] steel on [points] points, repaired [.]; [LAZYLEN(afflictions)] affliction(s) remain.")

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
			spent(E)
		var/list/organ_data = H.species.has_limbs[limb_tag]
		var/limb_path = organ_data["path"]
		var/obj/item/organ/external/new_limb = new limb_path(H)
		new_limb.robotize(H.synthetic ? H.synthetic.company : null)
		new_limb.sync_colour_to_human(H)
		regrown++
	for(var/organ_tag in H.species.has_organ)
		if(H.organ_in(organ_tag))
			continue
		var/organ_type = H.species.has_organ[organ_tag]
		new organ_type(H, TRUE) // takes its place in its limb
		regrown++
	if(regrown)
		H.regenerate_icons()
		log_game("NANOFORM: [key_name(H)] regrew [regrown] part(s).")
	return regrown

// --- Core dormancy ---------------------------------------------------------------------

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
	/// The mob whose body status question (/datum/act/body_status) we answer: held alive.
	var/mob/living/held_mob


/datum/affliction/core_dormancy/on_added()
	..()
	set_severity(AFFLICTION_SEVERITY_TERMINAL)
	rel_set(src, nameof(held_mob), owner)
	observe(held_mob, /datum/act/body_status, src, instead())
	// Without a control cluster to work through, the core is repaired on the body itself.
	observe(held_mob, /datum/act/tool_act, src, instead(then(PROC_REF(on_body_screwdriver))))
	observe(held_mob, /datum/act/attackby, src, instead(then(PROC_REF(on_body_attackby))))
	log_game("NANOFORM: [key_name(held_mob)] entered core dormancy at [AREACOORD(held_mob)].")
	play_sfx(held_mob, SFX_VOICE_BORG_DEATHSOUND)
	held_mob.visible_message(span_bold("[held_mob.name]") + " shudders and retreats inwards, coalescing into a single core component!")
	to_chat(held_mob, span_warning("Your swarm has lost cohesion! You are locked in your core control module until you are repaired. Instructions for your revival are shown when your module is examined."))
	var/datum/forms/protean/F = held_mob.get_protean_forms()
	if(!F)
		return
	// Folding up inside a belly, closet, mech or holder would move the core out of
	// its container; there the swarm collapses where it is instead.
	if(isturf(held_mob.loc))
		F.enter_rig()
	else
		log_game("NANOFORM: [key_name(held_mob)] went dormant inside [held_mob.loc] ([held_mob.loc.type]); not folding into the control cluster.")
	F.rig?.go_inert()

/datum/affliction/core_dormancy/on_removed()
	release()
	return ..()

// a dormant core is released.
/datum/affliction/core_dormancy/on_destroy(force)
	release()
	..()

/datum/affliction/core_dormancy/proc/release()
	if(after_pending(src, "reboot_timer"))
		cancel_after(src, "reboot_timer")
	if(!held_mob)
		return
	unobserve(held_mob, /datum/act/body_status, src)
	unobserve(held_mob, /datum/act/tool_act, src)
	unobserve(held_mob, /datum/act/attackby, src)
	var/datum/forms/protean/F = held_mob.get_protean_forms()
	F?.rig?.wake()
	log_game("NANOFORM: [key_name(held_mob)] left core dormancy.")
	rel_clear(src, nameof(held_mob))

/// Dormant cores don't progress or heal on their own; they stay down.
/datum/affliction/core_dormancy/progress()
	pending_treatment = 0

/datum/affliction/core_dormancy/proc/open_panel()
	if(revival_step == DORMANCY_SEALED)
		revival_step = DORMANCY_OPEN

/// True when the core is repaired on the body rather than through the control
/// cluster: the protean has no cluster, or is not folded into it.
/datum/affliction/core_dormancy/proc/repaired_on_body()
	var/datum/forms/protean/F = held_mob?.get_protean_forms()
	return !F?.in_rig()

/datum/affliction/core_dormancy/proc/on_body_screwdriver(datum/act/tool_act/use)
	SHOULD_NOT_SLEEP(TRUE)
	if(use.tool_quality != TOOL_SCREWDRIVER || use.secondary)
		return HOOK_DECLINE
	var/mob/living/user = use.user
	var/obj/item/tool = use.tool
	if(revival_step != DORMANCY_SEALED || !repaired_on_body())
		return HOOK_DECLINE
	repair_with(tool, user, use.target)
	return ITEM_INTERACT_SUCCESS

/datum/affliction/core_dormancy/proc/on_body_attackby(datum/act/attackby/use)
	SHOULD_NOT_SLEEP(TRUE)
	var/obj/item/W = use.item
	var/mob/living/user = use.user
	if(!repaired_on_body() || !is_repair_item(W))
		return HOOK_DECLINE
	repair_with(W, user, use.target)
	return TRUE

/// Whether `W` is the tool for the current revival step.
/datum/affliction/core_dormancy/proc/is_repair_item(obj/item/W)
	switch(revival_step)
		if(DORMANCY_SEALED)
			return W.has_tool_quality(TOOL_SCREWDRIVER)
		if(DORMANCY_OPEN)
			return istype(W, /obj/item/protean_reboot)
		if(DORMANCY_PROGRAMMED)
			return istype(W, /obj/item/stack/nanopaste)
		if(DORMANCY_PASTED)
			return istype(W, /obj/item/shockpaddles)
	return FALSE

/// Advance one revival step with `W`, working on `site` (the control cluster,
/// or the protean's body when there is no cluster): a timed action, finished by repair_step_done().
/datum/affliction/core_dormancy/proc/repair_with(obj/item/W, mob/living/user, atom/site)
	var/mob/living/patient = held_mob
	if(!patient || !istype(user) || !is_repair_item(W))
		return
	var/step = revival_step
	switch(step)
		if(DORMANCY_SEALED)
			playsound(site, W.usesound, 50, 1)
		if(DORMANCY_PASTED)
			var/obj/item/shockpaddles/paddles = W
			if(!paddles.can_use(user))
				return
			to_chat(user, span_notice("You hook up [W] to the contact points in the maintenance assembly."))
			perform_op(user, src, "paddles_charge", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("tool" = W, "step" = step, "site" = site))
			return
	perform_op(user, src, "repair_step", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("tool" = W, "step" = step, "site" = site, "time" = 5 SECONDS))

// The revival steps are ops of the dormancy (it is their holder): whoever works on the cluster, or on the body, is the actor and stays beside the site.
CAPABILITIES(/datum/affliction/core_dormancy)
	op("paddles_charge", ai(), needs(req_capable()), takes("tool", "step", "site"), wait(5 SECONDS), then(PROC_REF(paddles_charge)))
	op("repair_step", ai(), needs(req_capable()), takes("tool", "step", "site", "time"), wait(PROC_REF(repair_step_time)), then(PROC_REF(repair_step_done)))

/// The paddles charge, then the shock follows a second later.
/datum/affliction/core_dormancy/proc/paddles_charge(datum/act/op/A)
	var/obj/item/W = A.arg("tool")
	var/mob/living/user = A.actor
	var/atom/site = A.arg("site")
	var/step = A.arg("step")
	if(QDELETED(W) || QDELETED(site) || !user.Adjacent(site))
		return
	play_sfx(site, SFX_MACHINES_DEFIB_CHARGE)
	perform_op(user, src, "repair_step", null, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("tool" = W, "step" = step, "site" = site, "time" = 1 SECOND))

/datum/affliction/core_dormancy/proc/repair_step_time(datum/act/op/A)
	return A.arg("time")

/datum/affliction/core_dormancy/proc/repair_step_done(datum/act/op/A)
	var/obj/item/W = A.arg("tool")
	var/mob/living/user = A.actor
	var/atom/site = A.arg("site")
	var/step = A.arg("step")
	var/mob/living/patient = held_mob
	if(!patient || revival_step != step || QDELETED(W) || QDELETED(site) || !user.Adjacent(site))
		return
	switch(step)
		if(DORMANCY_SEALED)
			to_chat(user, span_notice("You unscrew the maintenance panel on [site]."))
			open_panel()
		if(DORMANCY_OPEN)
			if(patient.mend(TREAT_CALIBRATION, 1))
				play_sfx(site, SFX_ITEMS_DECONSTRUCT)
				to_chat(user, span_notice("You carefully slot [W] into [site]."))
				consume(W, user)
		if(DORMANCY_PROGRAMMED)
			var/obj/item/stack/nanopaste/paste = W
			if(paste.use(1) && patient.mend(TREAT_PLATING_REPAIR, 1))
				play_sfx(site, SFX_EFFECTS_OINTMENT)
				to_chat(user, span_notice("You slather the interior confines of [site] with [W]."))
		if(DORMANCY_PASTED)
			play_sfx(site, SFX_MACHINES_DEFIB_ZAP)
			if(patient.mend(TREAT_DEFIBRILLATION, 1))
				play_sfx(site, SFX_MACHINES_DEFIB_SUCCESS)
				gibs(get_turf(site), null, /obj/effect/gibspawner/robot)
				site.atom_say("Contact received! Reassembly nanites calibrated. Estimated time to resucitation: 1 minute 30 seconds")
	log_game("NANOFORM: [key_name(user)] worked on [key_name(patient)]'s dormant core with [W] via [site]; step [step] -> [revival_step].")

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
		after(src, DORMANCY_REBOOT_TIME, PROC_REF(complete_revival), key = "reboot_timer")
	return 1

/// Reassembly finished: rebuild cohesion and what the revival steps repaired,
/// then leave dormancy. Afflictions the revival didn't touch stay.
/datum/affliction/core_dormancy/proc/complete_revival()
	if(after_pending(src, "reboot_timer"))
		cancel_after(src, "reboot_timer")
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
	play_sfx(get_turf(patient), SFX_MACHINES_DING)

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
