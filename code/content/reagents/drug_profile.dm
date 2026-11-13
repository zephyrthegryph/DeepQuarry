// The drug profile: the data a drug declares about its drawbacks, read by the metabolism, the scanners and the medical book.
//
//   strains = alist(O_LIVER = DRUG_STRAIN_MODERATE)  slow organ damage per unit metabolised (a toxic lesion on the organ). Natural regeneration
//                                                    outpaces it while the organ is healthy; it accumulates when the organ is already damaged,
//                                                    doses repeat, or two drugs strain the same organ (the lesions simply add).
//   hides   = list(HIDE_FEVER)                       readings this drug masks on instruments while it is in the blood (diagnose() applies them).
//   drains_blood = 2                                 blood lost per unit metabolised (dermaline); the book names it as a drawback.
//   purges_stomach = TRUE                            every other reagent still in the stomach is flushed out each metabolism tick (carthatoline).
//   slows_other = alist(TREAT_BURN_CARE = 0.85)      on a limb where this drug is treating wounds of that mechanism, the limb's other wounds heal
//                                                    naturally at this fraction (kelotane): per limb, never body-wide.
//   clot_risk = 5                                    percent per unit metabolised of an ischemic event (a lesion on the brain or the heart) while the heart
//                                                    is damaged or the systolic pressure is low (myelamine).
//   adds    = a /datum/affliction/chem_side_effect (or /datum/affliction/nausea, /seizure) with caused_by_chems: the pharmacology files.
//
// Both tables are constant per type (shared like treatment_tags, /datum/reagent/New()).

/datum/reagent
	/// O_* organ tag -> toxic-lesion damage per unit metabolised in the blood.
	var/alist/strains
	/// HIDE_* readings masked on instruments while at least DRUG_HIDE_MIN_VOLUME is in the blood.
	var/list/hides
	/// Blood lost per unit of this reagent metabolised in the blood (0 = none).
	var/drains_blood = 0
	/// TRUE: every other reagent in the stomach is flushed out each tick this is metabolised.
	var/purges_stomach = FALSE
	/// TREAT_* -> scale (0 to 1): on a limb where this drug treats wounds of that mechanism, that limb's other wounds heal naturally at the scale.
	var/alist/slows_other
	/// Percent chance per unit metabolised of an ischemic event while the heart is damaged or the pressure is low (0 = no risk).
	var/clot_risk = 0

/// Every unit this reagent metabolises in the blood strains each organ in `strains`: a toxic lesion on it, through the injury pipeline.
/datum/reagent/proc/apply_strains(mob/living/carbon/M, removed)
	if(!strains || removed <= 0 || inert_for(M))
		return
	for(var/organ_tag in strains)
		var/obj/item/organ/O = M.organ_in(organ_tag)
		if(!O)
			continue
		var/amount = strains[organ_tag] * removed * species_mult(M)
		if(amount <= 0)
			continue
		M.injure(INJURY_BLUNT, amount, O, src, affliction = /datum/affliction/lesion/toxic_injury, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
		if(GLOB.chem_trace)
			log_world("CHEM: [id] strains [organ_tag] of [M] by [amount] (removed [removed])")

/// The drawbacks other than strain that a drug declares, applied once per blood metabolism tick (`removed` units).
/datum/reagent/proc/apply_drawbacks(mob/living/carbon/M, removed)
	if(removed <= 0 || inert_for(M))
		return
	if(drains_blood)
		apply_blood_drain(M, removed)
	if(purges_stomach)
		apply_stomach_purge(M)
	if(clot_risk)
		apply_clot_risk(M, removed)

/// Blood lost per unit metabolised (`drains_blood`).
/datum/reagent/proc/apply_blood_drain(mob/living/carbon/M, removed)
	if(!ishuman(M))
		return
	var/mob/living/carbon/human/H = M
	var/lost = H.remove_blood(drains_blood * removed)
	if(lost && GLOB.chem_trace)
		log_world("CHEM: [id] drains [lost] blood from [H] (removed [removed])")

/// Whatever else was swallowed and not yet absorbed is flushed out (`purges_stomach`); not this reagent itself, which is still on its way in.
/datum/reagent/proc/apply_stomach_purge(mob/living/carbon/M)
	if(!M.ingested?.total_volume)
		return
	for(var/datum/reagent/R as anything in M.ingested.reagent_list.Copy())
		if(R.id == id)
			continue
		if(GLOB.chem_trace)
			log_world("CHEM: [id] purges [R.volume]u of [R.id] from the stomach of [M]")
		M.ingested.del_reagent(R.id)

/// Why this body is at risk of a clot (`clot_risk`): a damaged heart or a low systolic pressure; null when it is not.
/mob/living/carbon/proc/clot_risk_reason()
	return null

/mob/living/carbon/human/clot_risk_reason()
	var/obj/item/organ/internal/heart = organ_in(O_HEART)
	if(heart && heart.max_damage && heart.damage / heart.max_damage >= DRUG_CLOT_HEART_DAMAGE_FRACTION)
		return "a damaged heart"
	var/list/pressure = body?.blood_pressure()
	if(pressure && pressure[1] < DRUG_CLOT_LOW_SYSTOLIC)
		return "a low blood pressure"
	return null

/// An ischemic event (`clot_risk`): a clot lodges in the brain or the heart and starves a patch of it of oxygen.
/datum/reagent/proc/apply_clot_risk(mob/living/carbon/M, removed)
	if(!ishuman(M))
		return
	var/mob/living/carbon/human/H = M
	var/reason = H.clot_risk_reason()
	if(!reason)
		return
	var/chance = min(100, clot_risk * removed * species_mult(M))
	if(!prob(chance))
		return
	var/organ_tag = pick(O_BRAIN, O_HEART)
	var/obj/item/organ/internal/O = H.organ_in(organ_tag)
	if(!O || O.is_robotic())
		return
	var/room = max(0, O.max_damage - O.damage)
	if(room <= 0)
		return
	O.add_lesion(/datum/affliction/lesion/ischemic_injury, min(DRUG_CLOT_ISCHEMIC_DAMAGE, room))
	log_game("CLOT: [id] clot lodged in the [organ_tag] of [key_name(H)] (risk from [reason]).")
	if(GLOB.chem_trace)
		log_world("CHEM: [id] clot in the [organ_tag] of [H]: [reason], chance [chance]%")

/// The scale on the natural healing of wound `W` on limb `E`: a drug in the blood with `slows_other` slows the limb's wounds it does not treat, but only on a
/// limb where it is treating wounds of its mechanism (kelotane slows a cut next to a burn it is healing, not a cut on the other arm).
/mob/living/carbon/proc/natural_healing_scale(obj/item/organ/external/E, datum/affliction/wound/W)
	. = 1
	for(var/datum/reagent/R as anything in bloodstr?.reagent_list)
		if(!R.slows_other)
			continue
		for(var/tag in R.slows_other)
			if(W.treatment_rate(tag))
				continue // a wound it treats is not slowed
			if(!limb_has_wound_treated_by(E, tag))
				continue
			. *= R.slows_other[tag]

/// Does limb `E` carry an open wound that mechanism `tag` treats?
/mob/living/carbon/proc/limb_has_wound_treated_by(obj/item/organ/external/E, tag)
	for(var/datum/affliction/wound/W as anything in E.get_wounds())
		if(W.damage > 0 && W.treatment_rate(tag))
			return TRUE
	return FALSE

/// Is a reading (HIDE_*) masked on this mob's instruments by a drug in its blood?
/mob/living/proc/reading_hidden(key)
	return FALSE

/mob/living/carbon/reading_hidden(key)
	for(var/datum/reagent/R as anything in bloodstr?.reagent_list)
		if(R.hides && (key in R.hides) && R.volume >= DRUG_HIDE_MIN_VOLUME)
			return TRUE
	return FALSE

/// Every reading hidden at once (the diagnosis asks once per scan), as a list of HIDE_* keys; null when nothing is masked.
/mob/living/proc/hidden_readings()
	return null

/mob/living/carbon/hidden_readings()
	var/list/out
	for(var/datum/reagent/R as anything in bloodstr?.reagent_list)
		if(!R.hides || R.volume < DRUG_HIDE_MIN_VOLUME)
			continue
		for(var/key in R.hides)
			LAZYOR(out, key)
	return out

/// TRUE: every strain and mask a drug applies is written to the world log (an admin or a test sets it to follow a drug that behaves strangely).
GLOBAL_VAR_INIT(chem_trace, FALSE)
