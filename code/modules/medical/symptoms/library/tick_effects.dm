// Symptom tick effects.
//
// Most symptoms in this codebase are pure presentation — messages,
// emotes, scanner phrases. A handful, when they fire from a high-severity
// OD source, should actually *do* something to the patient: a fever
// raises body temperature, palpitations occasionally stress the heart,
// visible bleeding drains blood. These overrides hook into the per-tick
// `tick(M, source)` channel so the in-the-moment pressure ratchets up
// alongside the named symptom rather than only existing as flavor text.
//
// **Scoped to Overdose-subcategory conditions.** Non-OD conditions that
// share these symptoms (cellulitis fever, sepsis chills, etc.) keep
// their existing per-condition tick math without double-application from
// the symptom side. The aim was to make Critical OD bite harder; we
// don't want to retune every other condition that happens to surface
// these symptoms.
//
// All effects scale with the source condition's severity (severity / 100
// multiplier) so a Mild-band symptom does little, while a Critical-band
// symptom does the full magnitude. The patient-message / emote drip from
// the parent tick() still fires; we call `..()` first to preserve it.

/datum/medical_symptom/fever_sensation/tick(mob/living/M, datum/medical_issue/condition/source)
	. = ..()
	if(!M || !source)
		return
	if(source.subcategory != "Overdose")
		return
	var/scale = source.severity / 100
	if(scale <= 0)
		return
	// Push body temperature up. At sev 100, +0.4 K/tick — a sustained
	// Critical fever drifts the patient toward heatstroke threshold over
	// minutes, giving the metric_threshold/heat_exposure cause room to
	// fire without the symptom being responsible for spawning the
	// condition itself.
	M.bodytemperature += 0.4 * scale


/datum/medical_symptom/chills/tick(mob/living/M, datum/medical_issue/condition/source)
	. = ..()
	if(!M || !source)
		return
	if(source.subcategory != "Overdose")
		return
	var/scale = source.severity / 100
	if(scale <= 0)
		return
	// Equivalent to fever in the other direction — drop temp toward
	// hypothermia. Same magnitude.
	M.bodytemperature -= 0.4 * scale


/datum/medical_symptom/palpitations/tick(mob/living/M, datum/medical_issue/condition/source)
	. = ..()
	if(!M || !source)
		return
	if(source.subcategory != "Overdose")
		return
	var/scale = source.severity / 100
	if(scale <= 0.6)
		return
	// At Severe / Critical bands, an active palpitations symptom
	// occasionally inflicts a small amount of direct heart strain.
	// Probability scales with severity above the Severe gate; effect is
	// ~0.4 internal damage per fire, ~5% per tick at Critical. Lets
	// hyperzine and similar cardiac ODs feel risky even before the
	// severity_gate spawns heart_damage.
	if(prob(5 * scale) && ishuman(M))
		var/mob/living/carbon/human/H = M
		var/obj/item/organ/internal/heart/heart = H.internal_organs_by_name[O_HEART]
		if(heart)
			heart.take_damage(0.4)


/datum/medical_symptom/bleeding_visible/tick(mob/living/M, datum/medical_issue/condition/source)
	. = ..()
	if(!M || !source || !ishuman(M))
		return
	if(source.subcategory != "Overdose")
		return
	var/scale = source.severity / 100
	if(scale <= 0)
		return
	// Drains blood. At sev 100 the symptom drains ~1u/tick — still slow
	// enough that a hematostat or bicaridine cure can recover, but
	// sustained exposure during a Critical bleeding-OD can drive
	// hypovolemia by itself. Bleeding-from-overdose is the rationale.
	var/mob/living/carbon/human/H = M
	if(H.vessel)
		H.vessel.remove_reagent(REAGENT_ID_BLOOD, 1.0 * scale)


/datum/medical_symptom/cyanosis/tick(mob/living/M, datum/medical_issue/condition/source)
	. = ..()
	if(!M || !source)
		return
	if(source.subcategory != "Overdose")
		return
	var/scale = source.severity / 100
	if(scale <= 0.5)
		return
	// Cyanosis fires only when the source is Severe-or-worse. Adds a
	// small oxy loss to reflect the tissue-level oxygen failure the
	// blue tint represents — already-existing oxy damage from the
	// underlying condition just gets amplified.
	M.adjustOxyLoss(0.5 * scale)


/datum/medical_symptom/labored_breathing/tick(mob/living/M, datum/medical_issue/condition/source)
	. = ..()
	if(!M || !source)
		return
	if(source.subcategory != "Overdose")
		return
	var/scale = source.severity / 100
	if(scale <= 0.6)
		return
	// At Critical, ongoing labored breathing reflects that the patient
	// isn't moving enough air. Small oxy loss; severity_gate complications
	// (respiratory_failure spawn) handle the catastrophic outcome.
	M.adjustOxyLoss(0.4 * scale)


/datum/medical_symptom/sharp_chest_pain/tick(mob/living/M, datum/medical_issue/condition/source)
	. = ..()
	if(!M || !source)
		return
	if(source.subcategory != "Overdose")
		return
	var/scale = source.severity / 100
	if(scale <= 0.5)
		return
	// Severe ischemic chest pain has a small chance per tick of stunning
	// the patient as the pain peaks. Doesn't damage; just incapacitates
	// briefly.
	if(prob(3 * scale))
		M.Weaken(2)


/datum/medical_symptom/jaundice/tick(mob/living/M, datum/medical_issue/condition/source)
	. = ..()
	if(!M || !source)
		return
	if(source.subcategory != "Overdose")
		return
	var/scale = source.severity / 100
	if(scale <= 0.5)
		return
	// Severe jaundice means the liver isn't clearing bilirubin — let a
	// tiny amount of toxic backlog accumulate.
	M.adjustToxLoss(0.3 * scale)
