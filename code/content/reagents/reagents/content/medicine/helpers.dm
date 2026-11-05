/// Instant wound closure for overdose / clotting side effects (a burst, not a
/// continuous treatment). B13: goes through mend(), so the tags' biology gate
/// applies — a robotic limb is not clotted by a drug. Bleeding wounds take
/// tissue repair; internal (arterial) ones take vessel repair.
/proc/dq_reagent_close_wounds(obj/item/organ/external/O, amount, bleeding = TRUE, internal = TRUE)
	var/mob/living/L = O?.owner
	if(!L)
		return 0
	. = 0
	if(bleeding)
		. += L.mend(TREAT_TISSUE_REPAIR, amount, O)
	if(internal)
		. += L.mend(TREAT_VESSEL_REPAIR, amount, O)

/// B13: a reagent that knits a fracture outright (bone regrowth, calcium
/// miracles). Routed through mend(TREAT_BONE_SETTING) so only organic bone
/// knits, and refused while the limb is still too damaged to hold.
/proc/dq_reagent_knit_fracture(obj/item/organ/external/O)
	var/mob/living/L = O?.owner
	if(!L || !O.is_fractured())
		return 0
	if(O.get_trauma() > O.min_broken_damage * CONFIG_GET(number/organ_health_multiplier))
		return 0 // would just break again
	return L.mend(TREAT_BONE_SETTING, DQ_REAGENT_KNIT_AMOUNT, O)

/// Cryo-chemical regeneration: every tissue mechanism at once. Only for the
/// temperature/death-gated cryo chems, whose gate a continuous tag can't express.
/proc/dq_cryo_mend(mob/living/carbon/M, amount)
	M.mend(TREAT_GENETIC_REPAIR, amount)
	M.mend(TREAT_OXYGENATION, amount)
	M.mend(TREAT_TISSUE_REPAIR, amount)
	M.mend(TREAT_BURN_CARE, amount)
	M.mend(TREAT_ANTITOXIN, amount)

/// P2-D6 / P2-K6: the -daxon organ-repair family as data. Repair itself is
/// each drug's organ treatment tag; this shared body applies the side effects:
/// confusion while a targeted (organic) organ is damaged, then either the clash
/// with a partner reagent or the drug's solo effect. A drug sets its organ
/// targets and partners by overriding the two getters.
TYPE_TABLE_DECLARE(/datum/reagent, daxon_organs, null)

TYPE_TABLE_DECLARE(/datum/reagent, daxon_partners, null)

/datum/reagent/proc/daxon_clash(mob/living/carbon/human/H, removed)
	return

/datum/reagent/proc/daxon_alone(mob/living/carbon/human/H, removed)
	return

/datum/reagent/proc/daxon_affect(mob/living/carbon/M, removed)
	if(!ishuman(M))
		return
	var/mob/living/carbon/human/H = M
	var/list/targets = TYPE_TABLE_GET(src, daxon_organs)
	for(var/obj/item/organ/internal/I as anything in H.internal_organ_list())
		if(I.is_robotic() || !(I.organ_tag in targets))
			continue
		if(I.damage > 0)
			H.status_at_least(STAT_CONFUSED, 2)
			break
	for(var/partner in TYPE_TABLE_GET(src, daxon_partners))
		if(H.body?.reagent_volume(partner))
			daxon_clash(H, removed)
			return
	daxon_alone(H, removed)

/// The gender change drug asks before it acts, for pref sake.
/proc/change_drug_ask(mob/living/carbon/human/M, gender_change)
	if(QDELETED(M))
		return
	//allow it to bug them again now that we've waited
	human_misc_of(M).set_gender_change_cooldown(0)
	open_request(M, /datum/prompt/yes_no/gender_change_drug, TYPE_PROC_REF(/mob/living/carbon/human, gender_change_drug_answered), answerer = M, gender_change = gender_change, timeout = 0)

/datum/prompt/yes_no/gender_change_drug
	recheck_on_open = TRUE
	title = "Warning"
	question = "This chemical will change your gender, proceed?"
	var/gender_change

/mob/living/carbon/human/proc/gender_change_drug_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/yes_no/gender_change_drug/ask = A.answer
	change_gender_identity(ask.gender_change)
	change_gender(ask.gender_change)
	to_chat(src, span_warning("You feel like a new person."))

/datum/body_effect/liquidhealer
	stacks = MODIFIER_STACK_FORBID
	tick_interval = 2 SECONDS
	name = REAGENT_ID_LIQUIDHEALER
	desc = "You are filled with an overwhelming healing."

	on_created_text = span_critical("You feel your body's natural healing quick into overdrive!")
	on_expired_text = span_notice("Your body returns to normal.")

	factors = alist(STAT_HEALING_RECEIVED = 1.2)

/datum/body_effect/liquidhealer/on_tick(mob/living/L)
	if(L.stat == DEAD)
		L.end_body_effect(type)
		return

	// A regeneration power, not a reagent: it mends by mechanism, organic
	// and synthetic alike (the old code repaired robolimbs too).
	L.mend(TREAT_TISSUE_REPAIR, 1)
	L.mend(TREAT_BURN_CARE, 1)
	L.mend(TREAT_PLATING_REPAIR, 1)
	L.mend(TREAT_WIRING_REPAIR, 1)
	L.mend(TREAT_ANTITOXIN, 1)
	L.mend(TREAT_OXYGENATION, 1)
	L.mend(TREAT_GENETIC_REPAIR, 1)
