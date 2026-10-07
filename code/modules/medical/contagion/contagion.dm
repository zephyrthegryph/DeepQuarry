// /datum/affliction/contagion — an infectious disease, as an affliction.
//
// This replaces the old /datum/disease system (code/datums/diseases). A
// contagion is a systemic affliction on a humanoid body:
//
//   old /datum/disease            now
//   stage / max_stages            `stage` 1..max_stages; severity mirrors it
//                                 (100 * stage / max_stages) so vitals,
//                                 symptom bands and factor bands follow
//   stage_prob                    per-tick chance to advance a stage while
//                                 the host has not got it under control
//   stage_act()                   the per-type stage hook, called from
//                                 progress(); symptoms and stage factors
//                                 carry the presentation
//   cures / cure_chance           `cures` reagent ids read from the body's
//                                 treatment snapshot; while present each
//                                 tick rolls cure_chance to regress or cure
//   natural immunity timer        the host immune response: `immunity`
//                                 builds each tick from TREAT_REGENERATION
//                                 (rest, sleep, nutrition), TREAT_ANTIMICROBIAL
//                                 and lying down. Past CONTAGION_IMMUNITY_CONTROL
//                                 the disease stops advancing and regresses;
//                                 at CONTAGION_IMMUNITY_CLEAR a curable
//                                 disease resolves with lasting immunity
//   visibility / DISCOVERED       presentation + perceived_by() (diagnosis)
//   viable_mobtypes / required_organs  body_plans / biology + can_afflict()
//   affected_mob                  the owning body's mob (`owner`); `host` is
//                                 the typed humanoid view, set while attached
//   spread()                      /datum/affliction_trigger/contagion, run
//                                 from a parkable periodic lane (see
//                                 transmission.dm), not per-tick polling
//   resistances                   body.contagion_immunities
//
// Outcomes are not "inject cure, done": a case can resolve on the host's own
// immune response (faster with rest and antimicrobials), be cured by the
// right reagents, settle into an asymptomatic carrier (species immunity:
// the host spreads it without suffering it), need surgery (appendicitis:
// the required organ goes, the disease goes), or run to a terminal stage.
// Detached (unattached) contagions are the portable form carried in blood
// data, decals, syringes and cultures; infect() copies one into a body.
/datum/affliction/contagion
	name = "No disease"
	category = "Infectious"
	subcategory = "Viral"
	biology = BIOLOGY_ORGANIC
	body_plans = BODY_PLAN_HUMANOID
	progression_rate = 0
	severity_per_injury = 0
	restoration_rate = 100
	presentation = PRESENT_INTERNAL | PRESENT_LAB
	/// Rest, sleep and nutrition feed the immune response; spaceacillin-type
	/// antimicrobials boost it. Amounts are immunity points per tick.
	treated_by = list(TREAT_REGENERATION = CONTAGION_IMMUNE_BASE, TREAT_ANTIMICROBIAL = CONTAGION_IMMUNE_ANTIMICROBIAL)
	min_symptoms = 0
	max_symptoms = 2
	abstract_type = /datum/affliction/contagion

	//Flags
	var/visibility_flags = 0
	var/disease_flags = CURABLE|CAN_CARRY|CAN_RESIST

	//Fluff
	/// Used for identification of viruses in the Medical Records Virus Database
	var/medical_name
	var/form = "Virus"
	var/desc = ""
	var/agent = "some microbes"
	var/spread_text = ""
	var/cure_text = ""

	//Stages. `stage` (inherited) is the numeric stage 1..max_stages.
	var/max_stages = 0
	var/stage_prob = 4

	/// The fraction of stages the virus must at least be at to show up on medical HUDs. Rounded up.
	var/discovery_threshold = 0.5

	// Other
	/// Reagent ids that cure this disease (all of them with NEEDS_ALL_CURES).
	var/list/cures
	var/cure_chance = 8
	var/permeability_mod = 1
	var/danger = DISEASE_MINOR
	/// Organ typepaths the host must have; losing one ends the disease.
	var/list/required_organs
	var/list/strain_data
	var/initial = TRUE

	/// The host immune response, 0..CONTAGION_IMMUNITY_CLEAR.
	var/immunity = 0
	/// Multiplier on the immune response this pathogen provokes. 0 = the
	/// host never fights it off on its own.
	var/immunogenicity = 1
	/// Immunity accrued from this tick's continuous treatment.
	var/tmp/pending_immunity = 0

/// Typed view of the owner while attached (contagions are humanoid-only).
/datum/affliction/contagion/var/tmp/mob/living/carbon/human/host
/// DISEASE_SPREAD_* routes.
/datum/affliction/contagion/var/spread_flags = DISEASE_SPREAD_AIRBORNE
TRACKED(/datum/affliction/contagion, spread_flags)
/// Strain modifier bits (NEEDS_ALL_CURES, DORMANT, SPREAD_DEAD, PROCESSING, ...).
/datum/affliction/contagion/var/virus_modifiers = NEEDS_ALL_CURES
TRACKED(/datum/affliction/contagion, virus_modifiers)
/datum/affliction/contagion/var/infectivity = 10
TRACKED(/datum/affliction/contagion, infectivity)

REGISTRY_MEMBERSHIP(/datum/affliction/contagion, REGISTRY_ACTIVE_DISEASES)

/// Contagions are systemic: whatever arguments a subtype's constructor takes,
/// the affliction location is null.
/datum/affliction/contagion/New()
	if(isnull(stage))
		stage = 1
	..(null)
	// Its declared spread work starts when it joins a body (on_added()), not here: a contagion is
	// also a template that is copied into a body and dropped, and a declaration started on the
	// template would give it an OM record that keeps it alive (an ownership-audit orphan).

// --- Joining and leaving a body ----------------------------------------------------

/// Viable on the declared body plans and biologies (a strain carrying
/// INFECT_SYNTHETICS also takes synthetic and nanoform bodies), and only on
/// hosts that carry every required organ.
/datum/affliction/contagion/can_afflict(datum/body/target_body, location)
	var/allowed = biology
	if(global_flag_check(virus_modifiers, INFECT_SYNTHETICS))
		allowed |= BIOLOGY_SYNTHETIC | BIOLOGY_NANOFORM
	if(!(target_body.plan_flag & body_plans) || !(target_body.biology_of(location) & allowed))
		return FALSE
	var/mob/living/carbon/human/H = target_body.owner
	if(!istype(H))
		return FALSE
	return has_required_organs(H)

/datum/affliction/contagion/proc/has_required_organs(mob/living/carbon/human/H)
	for(var/organ in required_organs)
		if(locate_in_list(H.internal_organ_list(), organ))
			continue
		if(locate_in_list(H.organs, organ))
			continue
		return FALSE
	return TRUE

/datum/affliction/contagion/on_added()
	..()
	rel_set(src, nameof(host), owner)
	// Its spread every() is gated on spread_lane_wanted, which re-evaluates once it has a host, and
	// again on each body it is handed on to.
	lifecycle_decls_init(src)
	sync_severity()
	registry_join(REGISTRY_ACTIVE_DISEASES, src)

/datum/affliction/contagion/on_removed()
	if(global_flag_check(virus_modifiers, PROCESSING))
		set_virus_modifiers(virus_modifiers & ~PROCESSING)
		End()
	..()
	registry_leave(REGISTRY_ACTIVE_DISEASES, src)
	rel_clear(src, nameof(host))

/datum/affliction/contagion/proc/try_infect(mob/living/infectee, make_copy = TRUE)
	return infect(infectee, make_copy)

/// Put this contagion (a copy of it, by default) into `infectee`'s body.
/// Returns the attached contagion, or null.
/datum/affliction/contagion/proc/infect(mob/living/infectee, make_copy = TRUE)
	if(!infectee?.body)
		return null
	var/datum/affliction/contagion/D = make_copy ? Copy() : src
	if(D.body)
		return null
	// A refused copy holds no references; it is simply dropped.
	if(!infectee.body.add_affliction(D))
		return null
	log_admin("[key_name(infectee)] has contracted the virus \"[D]\"")
	return D


// --- Stage and severity ----------------------------------------------------------

/// Severity mirrors the stage, so pain/consciousness scaling, symptom bands
/// and factor bands follow the disease's course.
/datum/affliction/contagion/proc/sync_severity()
	if(max_stages <= 0)
		return
	set_severity(round(100 * clamp(stage, 1, max_stages) / max_stages))

/datum/affliction/contagion/proc/set_stage(new_stage)
	new_stage = clamp(new_stage, 1, max(max_stages, 1))
	if(new_stage == stage)
		return FALSE
	var/old_stage = stage
	stage = new_stage
	if(!global_flag_check(virus_modifiers, DISCOVERED) && stage >= CEILING(max_stages * discovery_threshold, 1))
		set_virus_modifiers(virus_modifiers | DISCOVERED)
	sync_severity()
	OnStageChange(old_stage)
	return TRUE

/// Called when the stage moves.
/datum/affliction/contagion/proc/OnStageChange(old_stage)
	return

/// The affliction severity model is replaced by the stage model: severity
/// is written only through sync_severity(), never drifted.
/datum/affliction/contagion/tick_offline()
	return


// --- Treatment and the immune response ------------------------------------------

/// Continuous treatment (regeneration, antimicrobials) feeds the immune
/// response. Instant restoration (admin, magic) cures outright; any other
/// instant mend that reaches a contagion is a one-off immune boost.
/datum/affliction/contagion/receive_tagged_treatment(tag, amount, continuous = FALSE)
	if(continuous)
		pending_immunity += amount
		return amount
	if(tag == TREAT_RESTORATION)
		cure()
		return amount
	immunity = min(immunity + amount, CONTAGION_IMMUNITY_CLEAR)
	return amount

/// Worsening tags slow the immune response.
/datum/affliction/contagion/receive_worsening(amount)
	pending_immunity -= amount

/// Reagent cures present in the host: the count found, or 0 when
/// NEEDS_ALL_CURES is set and one is missing.
/datum/affliction/contagion/proc/has_cure()
	if(!(disease_flags & CURABLE) || !body)
		return 0
	var/cures_found = 0
	for(var/C_id in cures)
		if(body.reagent_volume(C_id) > 0)
			cures_found++
	if(global_flag_check(virus_modifiers, NEEDS_ALL_CURES) && cures_found < length(cures))
		return 0
	return cures_found

/// Immunity gained this tick: continuous treatment, lying down (bed rest),
/// the strong-immunity trait, scaled by how immunogenic the pathogen is.
/datum/affliction/contagion/proc/immune_gain()
	var/gain = pending_immunity
	pending_immunity = 0
	if(!host)
		return 0
	if(host.lying)
		gain += CONTAGION_IMMUNE_BEDREST
	if(has_trait(host, STRONG_IMMUNITY_TRAIT))
		gain *= 2
	return gain * immunogenicity

/// The disease's course for one tick. Replaces the base severity drift.
/datum/affliction/contagion/progress()
	pending_treatment = 0
	if(!host || max_stages <= 0)
		return
	if(global_flag_check(virus_modifiers, DORMANT))
		pending_immunity = 0
		return

	var/cure = has_cure()
	// Carriers host the pathogen without suffering it; only a cure touches them.
	if(global_flag_check(virus_modifiers, CARRIER) && !cure)
		pending_immunity = 0
		return

	if(!global_flag_check(virus_modifiers, PROCESSING))
		set_virus_modifiers(virus_modifiers | PROCESSING)
		Start()

	immunity = clamp(immunity + immune_gain(), 0, CONTAGION_IMMUNITY_CLEAR)
	var/controlled = immunity >= CONTAGION_IMMUNITY_CONTROL

	// Advance while nothing holds it back.
	if(!cure && !controlled && prob(stage_prob * body.get_factor(BF_PROGRESSION)))
		set_stage(stage + 1)

	// A cure in the blood, or an immune system in control, drives it back.
	if((cure || controlled) && prob(cure_chance))
		set_stage(stage - 1)

	if(!has_required_organs(host))
		log_game("CONTAGION: [key_name(host)] lost an organ [name] needs; the disease ends.")
		cure(FALSE)
		return

	if(disease_flags & CURABLE)
		if(cure && prob(cure_chance))
			log_game("CONTAGION: [key_name(host)] cured of [name] by reagents at stage [stage]/[max_stages].")
			cure()
			return
		if(immunity >= CONTAGION_IMMUNITY_CLEAR && stage <= 1)
			log_game("CONTAGION: [key_name(host)] cleared [name] on their own immune response.")
			to_chat(host, span_notice("You feel better."))
			cure()
			return

	if(host.stat == DEAD && !global_flag_check(virus_modifiers, SPREAD_DEAD))
		return
	stage_act()

/// Per-type stage effects, run once per tick while the disease is active
/// (not dormant, not a carrier without a cure). Returns FALSE when there is
/// no host to act on.
/datum/affliction/contagion/proc/stage_act()
	if(!host || QDELETED(src) || !body)
		return FALSE
	stage = min(stage, max_stages)
	return TRUE


// --- Ending ---------------------------------------------------------------------

/// Resolve the disease. `add_resistance` leaves lasting immunity on the body
/// when the disease allows it.
/datum/affliction/contagion/cure(add_resistance = TRUE)
	if(body && add_resistance && (disease_flags & CAN_RESIST))
		body.add_contagion_immunity(GetDiseaseID())
	..()

/// A self-limiting disease the host threw off (the old stage_act "You feel
/// better." branches).
/datum/affliction/contagion/proc/resolve_naturally()
	if(host)
		to_chat(host, span_notice("You feel better."))
		log_game("CONTAGION: [key_name(host)] recovered from [name].")
	cure()


// --- Presentation (diagnosis) ---------------------------------------------------

/// Hidden strains never show on a scanner; undiscovered ones only on lab
/// instruments (the body scanner); discovered ones on any internal analyzer.
/datum/affliction/contagion/perceived_by(datum/diagnostic_profile/P)
	if(visibility_flags & HIDDEN_SCANNER)
		return FALSE
	if(global_flag_check(virus_modifiers, DORMANT))
		return FALSE
	if(!global_flag_check(virus_modifiers, DISCOVERED) && !(P.senses & PRESENT_LAB))
		return FALSE
	return ..()

/datum/affliction/contagion/diagnostic_name()
	var/label = medical_name || name
	if(global_flag_check(virus_modifiers, CARRIER))
		return "[label] ([lowertext(form)], carrier)"
	return "[label] ([lowertext(form)], stage [stage]/[max_stages])"

/datum/affliction/contagion/diagnostic_hint(datum/diagnostic_profile/P)
	var/list/parts = list()
	if(spread_text)
		parts += "Spread: [spread_text]"
	if(cure_text)
		parts += "Cure: [cure_text]"
	if(immunity >= CONTAGION_IMMUNITY_CONTROL)
		parts += "host immune response is controlling it"
	return length(parts) ? jointext(parts, ". ") : null

/// The reference book lists the reagent cures beside the tag treatments.
/datum/affliction/contagion/effective_cures()
	. = ..()
	if(!(disease_flags & CURABLE))
		return
	for(var/id in cures)
		.[id] = (.[id] || 0) + cure_chance

/// The reference book and describing profiles read clinical_description.
/datum/affliction/contagion/configure(location)
	if(!clinical_description && desc)
		clinical_description = desc


// --- Identity and copies -------------------------------------------------------

/datum/affliction/contagion/proc/IsSame(datum/affliction/contagion/D)
	if(ispath(D))
		return istype(src, D)
	return istype(src, D.type)

/// A detached copy carrying this strain: its data and modifiers.
/datum/affliction/contagion/proc/Copy()
	var/datum/affliction/contagion/D = new type()
	D.strain_data = LAZYCOPY(strain_data)
	D.set_virus_modifiers(virus_modifiers & ~(PROCESSING | HAS_TIMER))
	return D

/datum/affliction/contagion/proc/GetDiseaseID()
	return "[type]"

/datum/affliction/contagion/proc/IsSpreadByBlood()
	return !!(spread_flags & DISEASE_SPREAD_BLOOD)

/datum/affliction/contagion/proc/IsSpreadByFluids()
	return !!(spread_flags & DISEASE_SPREAD_FLUIDS)

/datum/affliction/contagion/proc/IsSpreadByTouch()
	return !!(spread_flags & DISEASE_SPREAD_CONTACT)

/datum/affliction/contagion/proc/IsSpreadByAir()
	return !!(spread_flags & DISEASE_SPREAD_AIRBORNE)

/// Can it pass to another host at all (special and non-contagious strains don't)?
/datum/affliction/contagion/proc/is_spreadable()
	return !(spread_flags & (DISEASE_SPREAD_SPECIAL | DISEASE_SPREAD_NON_CONTAGIOUS))

/datum/affliction/contagion/proc/remove_virus()
	body?.remove_affliction(src)

// Called when the disease starts acting on a host
/datum/affliction/contagion/proc/Start()
	return

// Called when a disease is removed from a mob
/datum/affliction/contagion/proc/End()
	return

/// Called when the host dies (engineered strains fire their traits' death effects). The spread lane
/// needs nothing here: it reads "host.stat" as a derived input.
/datum/affliction/contagion/proc/OnDeath()
	return

// Adds a virus to the virus DB
/datum/affliction/contagion/proc/addToDB()
	if(GetDiseaseID() in GLOB.virusDB)
		return FALSE

	var/datum/data/record/v = new()

	v.fields["id"] = GetDiseaseID()
	v.fields["name"] = name
	v.fields["description"] = desc
	v.fields["form"] = form
	v.fields["agent"] = agent
	v.fields["cure"] = cure_text
	v.fields["spread"] = spread_text

	GLOB.virusDB["[GetDiseaseID()]"] = v

	return TRUE

/proc/get_disease_danger_value(danger)
	switch(danger)
		if(DISEASE_BENEFICIAL)
			return 1
		if(DISEASE_POSITIVE)
			return 2
		if(DISEASE_NONTHREAT)
			return 3
		if(DISEASE_MINOR)
			return 4
		if(DISEASE_MEDIUM)
			return 5
		if(DISEASE_HARMFUL)
			return 6
		if(DISEASE_DANGEROUS)
			return 7
		if(DISEASE_BIOHAZARD)
			return 8
		if(DISEASE_PANDEMIC)
			return 9

CAPABILITIES(/datum/affliction/contagion)
	ref_one(nameof(host))
