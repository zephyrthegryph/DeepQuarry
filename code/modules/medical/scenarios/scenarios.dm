// Scenario debug verbs — spawn a test patient pre-loaded with a curated
// set of cascading conditions.
//
// Each /datum/dq_medical_scenario subtype names a clinical situation
// and implements apply(H) to seed the right conditions on the right
// organs. Severity defaults to 40 so symptoms appear immediately but
// the player has time to react — no fast-forwarding.
//
// The verbs spawn the standard dq_spawn_medical_dummy human first and
// then apply the scenario. The dummy is sleeping so it doesn't wander
// off mid-test.


// --- Base ---------------------------------------------------------------

/datum/dq_medical_scenario
	/// Display name in the picker.
	var/name = "scenario"
	/// One-line clinical hook shown next to the name in the picker.
	var/description = ""

/// Default severity for a freshly-seeded condition. Lets symptoms show
/// up immediately on inspection without bypassing the progression curve.
#define DQ_SCENARIO_DEFAULT_SEVERITY 40

/datum/dq_medical_scenario/proc/apply(mob/living/carbon/human/H)
	return

/// Helper — spawn a condition on the named organ at the given severity.
/// Idempotent; if the same type is already present, leaves it alone.
/datum/dq_medical_scenario/proc/_seed(mob/living/carbon/human/H, organ_tag, condition_type, severity = DQ_SCENARIO_DEFAULT_SEVERITY)
	var/obj/item/organ/target
	if(organ_tag in list(O_HEART, O_LUNGS, O_BRAIN, O_LIVER, O_KIDNEYS, O_STOMACH, O_INTESTINE, O_SPLEEN, O_APPENDIX, O_EYES))
		target = H.internal_organs_by_name[organ_tag]
	else
		target = H.get_organ(organ_tag)
	if(!target)
		return null
	for(var/datum/medical_issue/condition/existing in target.medical_issues)
		if(existing.type == condition_type)
			return existing
	var/datum/medical_issue/condition/C = new condition_type()
	C.owner = H
	C.affectedorgan = target
	C.severity = severity
	LAZYADD(target.medical_issues, C)
	return C

/// Apply real damage to an external organ — goes through the same
/// path as combat hits, so blood, wounds, organ state, and the cause
/// system all see it. Use this instead of setting brute_dam directly
/// when the scenario is meant to model a real injury. After running,
/// `updatehealth()` is called so the mob's health bar reflects the
/// new state.
///
/// Note: the wound/cause system may roll the matching condition by
/// itself depending on probabilities; scenarios still call `_seed`
/// afterwards to guarantee the targeted condition is present (it's
/// idempotent).
/datum/dq_medical_scenario/proc/_apply_external_damage(mob/living/carbon/human/H, organ_tag, brute = 0, burn = 0, sharp = FALSE)
	var/obj/item/organ/external/E = H.get_organ(organ_tag)
	if(!E)
		return
	E.take_damage(brute, burn, sharp = sharp, edge = FALSE)
	H.updatehealth()


// --- Curated scenarios --------------------------------------------------

/datum/dq_medical_scenario/sharp_chest_stab
	name = "sharp chest stab"
	description = "Knife wound to the torso. Active hemorrhage, will cascade to shock."

/datum/dq_medical_scenario/sharp_chest_stab/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_TORSO, brute = 45, sharp = TRUE)
	_seed(H, BP_TORSO, /datum/medical_issue/condition/internal_hemorrhage, 45)


/datum/dq_medical_scenario/severe_burns
	name = "severe burns"
	description = "Burn victim, stage 2 burn shock. Watch the lungs."

/datum/dq_medical_scenario/severe_burns/apply(mob/living/carbon/human/H)
	// Distribute burn damage across multiple organs so the burn_shock
	// stage calculation picks up the body-surface burden.
	for(var/tag in list(BP_TORSO, BP_L_ARM, BP_R_ARM, BP_HEAD))
		_apply_external_damage(H, tag, burn = 30)
	_seed(H, BP_TORSO, /datum/medical_issue/condition/burn_shock, 50)


/datum/dq_medical_scenario/head_trauma
	name = "head trauma"
	description = "Blunt head injury with concussion. A second hit would be catastrophic."

/datum/dq_medical_scenario/head_trauma/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_HEAD, brute = 25)
	_seed(H, BP_HEAD, /datum/medical_issue/condition/concussion, 50)


/datum/dq_medical_scenario/double_head_hit
	name = "double head hit"
	description = "Patient took a second blow to an already-concussed head. Subdural hematoma."

/datum/dq_medical_scenario/double_head_hit/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_HEAD, brute = 45)
	_seed(H, BP_HEAD, /datum/medical_issue/condition/concussion, 35)
	_seed(H, BP_HEAD, /datum/medical_issue/condition/subdural_hematoma, 45)


/datum/dq_medical_scenario/crush_injury
	name = "crush injury"
	description = "Heavy blunt trauma across multiple limbs. Deep bruising and a fracture."

/datum/dq_medical_scenario/crush_injury/apply(mob/living/carbon/human/H)
	for(var/tag in list(BP_TORSO, BP_L_LEG, BP_R_LEG))
		_apply_external_damage(H, tag, brute = 30)
	_seed(H, BP_TORSO,  /datum/medical_issue/condition/deep_bruising)
	_seed(H, BP_L_LEG,  /datum/medical_issue/condition/untreated_fracture, 45)


/datum/dq_medical_scenario/dirty_wound
	name = "dirty wound, sepsis risk"
	description = "Old laceration neglected past first aid. Wound infection has set in."

/datum/dq_medical_scenario/dirty_wound/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_R_ARM, brute = 15, sharp = TRUE)
	var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
	if(arm)
		arm.germ_level = INFECTION_LEVEL_TWO
	_seed(H, BP_R_ARM, /datum/medical_issue/condition/wound_infection, 50)


/datum/dq_medical_scenario/cellulitis_advanced
	name = "advanced cellulitis"
	description = "Infection has progressed past the wound site. Cellulitis with sepsis brewing."

/datum/dq_medical_scenario/cellulitis_advanced/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_R_ARM, brute = 10, sharp = TRUE)
	var/obj/item/organ/external/arm = H.get_organ(BP_R_ARM)
	if(arm)
		arm.germ_level = INFECTION_LEVEL_TWO
	_seed(H, BP_R_ARM, /datum/medical_issue/condition/wound_infection, 65)
	_seed(H, BP_R_ARM, /datum/medical_issue/condition/cellulitis, 55)


/datum/dq_medical_scenario/severed_artery
	name = "severed artery"
	description = "Limb with a torn artery. Bleeding fast; treat or lose them to shock."

/datum/dq_medical_scenario/severed_artery/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_L_LEG, brute = 35, sharp = TRUE)
	_seed(H, BP_L_LEG, /datum/medical_issue/condition/lacerated_artery, 50)


/datum/dq_medical_scenario/chest_crush_pneumo
	name = "chest crush, pneumothorax"
	description = "Sharp chest trauma. Air in the pleural space; respiratory clock starts."

/datum/dq_medical_scenario/chest_crush_pneumo/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_TORSO, brute = 40, sharp = TRUE)
	_seed(H, BP_TORSO, /datum/medical_issue/condition/tension_pneumothorax, 45)


/datum/dq_medical_scenario/inhalation_burn
	name = "inhalation injury"
	description = "Fire exposure with airway burn. Watch oxygen sat."

/datum/dq_medical_scenario/inhalation_burn/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_HEAD, burn = 30)
	_seed(H, BP_HEAD, /datum/medical_issue/condition/airway_burn, 50)


/datum/dq_medical_scenario/limb_severed_tendon
	name = "severed tendon"
	description = "Sharp limb injury, tendon cut. Surgical fix only."

/datum/dq_medical_scenario/limb_severed_tendon/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_R_ARM, brute = 15, sharp = TRUE)
	_seed(H, BP_R_ARM, /datum/medical_issue/condition/tendon_severed)


/datum/dq_medical_scenario/multiple_trauma
	name = "polytrauma"
	description = "Multiple injuries: chest bleed, leg fracture, head concussion."

/datum/dq_medical_scenario/multiple_trauma/apply(mob/living/carbon/human/H)
	_apply_external_damage(H, BP_TORSO, brute = 30, sharp = TRUE)
	_apply_external_damage(H, BP_R_LEG, brute = 35)
	_apply_external_damage(H, BP_HEAD,  brute = 20)
	_seed(H, BP_TORSO, /datum/medical_issue/condition/internal_hemorrhage, 35)
	_seed(H, BP_R_LEG, /datum/medical_issue/condition/untreated_fracture, 40)
	_seed(H, BP_HEAD,  /datum/medical_issue/condition/concussion, 40)


// --- Verbs -------------------------------------------------------------

/// List the curated scenarios, keyed by display label for tgui_input_list.
/proc/_dq_list_medical_scenarios()
	var/list/L = list()
	for(var/T in subtypesof(/datum/dq_medical_scenario))
		var/datum/dq_medical_scenario/proto = T
		var/label = "[initial(proto.name)] — [initial(proto.description)]"
		L[label] = T
	return L

/// Shared spawning logic. Creates the dummy, applies the scenario, logs.
/// `silent` hides the scenario name/description from chat so the admin
/// running the random variant has to diagnose the patient blind. The
/// admin log always records the scenario name regardless — silent only
/// affects what the runner sees in their own chat.
/proc/_dq_run_scenario(mob/admin_mob, datum/dq_medical_scenario/scenario_path, silent = FALSE)
	if(!admin_mob)
		return
	var/turf/T = get_turf(admin_mob)
	if(!T)
		return
	var/mob/living/carbon/human/dummy = new /mob/living/carbon/human(T)
	dummy.real_name = "Scenario Patient #[rand(1000, 9999)]"
	dummy.name = dummy.real_name
	dummy.Sleeping(60 SECONDS)
	var/datum/dq_medical_scenario/S = new scenario_path()
	S.apply(dummy)
	if(silent)
		to_chat(admin_mob, span_notice("Spawned [dummy] with a random scenario — diagnose the patient yourself."))
	else
		to_chat(admin_mob, span_notice("Spawned [dummy] with scenario: <b>[S.name]</b> — [S.description]"))
	log_admin("[key_name(admin_mob)] ran medical scenario '[S.name]' on [dummy] at [T].")
	qdel(S)


ADMIN_VERB(dq_run_medical_scenario, R_DEBUG, "DQ Run Medical Scenario", "Spawn a test patient pre-loaded with a curated cascading-condition scenario.", ADMIN_CATEGORY_DEBUG)
	var/list/options = _dq_list_medical_scenarios()
	if(!length(options))
		to_chat(user.mob, span_warning("No /datum/dq_medical_scenario subtypes defined."))
		return
	var/picked_key = tgui_input_list(user.mob, "Which scenario?", "DQ Medical Scenario", options)
	if(!picked_key)
		return
	var/scenario_type = options[picked_key]
	_dq_run_scenario(user.mob, scenario_type)


ADMIN_VERB(dq_run_random_medical_scenario, R_DEBUG, "DQ Run Random Medical Scenario", "Spawn a test patient with one of the curated scenarios picked at random.", ADMIN_CATEGORY_DEBUG)
	var/list/all_types = subtypesof(/datum/dq_medical_scenario)
	if(!length(all_types))
		to_chat(user.mob, span_warning("No /datum/dq_medical_scenario subtypes defined."))
		return
	var/picked = pick(all_types)
	_dq_run_scenario(user.mob, picked, silent = TRUE)
