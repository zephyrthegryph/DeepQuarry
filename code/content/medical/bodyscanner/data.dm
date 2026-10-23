// Body scanner data builder.
//
// The patient's condition is the body scanner profile's diagnosis
// (code/modules/medical/diagnosis/): vitals, findings (conditions, lesions,
// wounds and presenting signs, with trends and hints) and per-limb bands,
// rendered by /datum/diagnosis/proc/report_data() into `diagnosis`.
//
// Per-limb and per-organ state (bands, fractures, bleeding, prostheses,
// necrosis, missing organs, implants) is the diagnosis `parts` list built by
// /datum/body/humanoid/diagnose_parts(). Alongside it: identity, abnormality
// flags and reagents.

/obj/machinery/bodyscanner/proc/dq_build_tgui_data()
	var/list/data = list()
	var/mob/living/carbon/human/occupant = occupant_of(src)
	data["occupied"] = occupant ? TRUE : FALSE

	if(!(occupant && ishuman(occupant)))
		data["occupant"] = list()
		return data

	var/mob/living/carbon/human/H = occupant
	var/list/occupantData = list()

	dq_emit_identity(H, occupantData)
	dq_emit_status(H, occupantData)
	dq_emit_vitals(H, occupantData)
	dq_emit_abnormalities(H, occupantData)
	dq_emit_reagents(H, occupantData)

	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/body_scanner, src) // D9: this scanner's baseline; the UI refresh doesn't move it
	occupantData["diagnosis"] = D.report_data()
	occupantData["healthBand"] = D.band
	occupantData["worstFinding"] = D.worst_finding_band()
	spent(D)

	// Pass-through fields the upstream layer still expects (vore prey
	// detection etc.). dq_build_tgui_data fills them via the existing
	// helper so we keep parity with non-DQ features.
	occupantData = get_vored_occupant_data(occupantData, H)

	data["occupant"] = occupantData
	return data


// --- field emitters -----------------------------------------------------

/obj/machinery/bodyscanner/proc/dq_emit_identity(mob/living/carbon/human/H, list/out)
	out["name"] = H.name
	var/species_text = H.species.name
	if(H.custom_species)
		if(H.species.name == SPECIES_CUSTOM || H.species.name == SPECIES_HANNER)
			species_text = "[H.custom_species]"
		else
			species_text = "[H.custom_species] \[Similar biology to [H.species.name]\]"
	out["species"] = species_text


/obj/machinery/bodyscanner/proc/dq_emit_status(mob/living/carbon/human/H, list/out)
	var/stat = H.stat
	var/fakedeath = FALSE
	if(H.status_flags & FAKEDEATH)
		stat = DEAD
		fakedeath = TRUE
	out["stat"] = stat
	out["fakedeath"] = fakedeath


/obj/machinery/bodyscanner/proc/dq_emit_vitals(mob/living/carbon/human/H, list/out)
	out["paralysisSeconds"] = round(H.status_seconds(STAT_PARALYZED))


/obj/machinery/bodyscanner/proc/dq_emit_abnormalities(mob/living/carbon/human/H, list/out)
	out["hasVirus"] = H.is_infective()
	out["hasBorer"] = H.has_brain_worms()
	out["blind"] = (H.sdisabilities & BLIND)
	out["nearsighted"] = H.is_nearsighted()
	out["brokenspine"] = (H.disabilities & SPINE)
	out["husked"] = (H.has_mutation(HUSK))

	var/has_withdrawl = FALSE
	for(var/addic in H.get_all_addictions())
		var/level = H.get_addiction_to_reagent(addic)
		if(level > 0 && level < 80)
			has_withdrawl = TRUE
			break
	out["hasWithdrawl"] = has_withdrawl

	out["allergens"] = assembly_allergy_list(H.species.allergens, H.species.medallergens)
	out["hasAllergens"] = islist(out["allergens"])

	var/list/wire_colors = H.body_effect_wire_colors()
	out["colourblind"] = wire_colors ? LAZYLEN(wire_colors) : null


/obj/machinery/bodyscanner/proc/dq_emit_reagents(mob/living/carbon/human/H, list/out)
	var/list/reagentData = list()
	if(H.reagents.reagent_list.len >= 1)
		for(var/datum/reagent/R in H.reagents.reagent_list)
			// `R.scannable` is the MIN scan_level needed to detect this reagent
			// (0 BENEFICIAL .. 3 SECRETIVE .. 99 UNSCANNABLE). Skip when our
			// scan_level can't reach it. The previous `>=` was inverted —
			// it hid every reagent the scanner SHOULD have shown.
			if(R.scannable > scan_level)
				continue
			reagentData += list(list(
				"name"     = R.name,
				"amount"   = R.volume,
				"overdose" = (R.overdose && R.volume > R.overdose) ? TRUE : FALSE,
			))
	out["reagents"] = length(reagentData) ? reagentData : null

	var/list/ingestedData = list()
	if(H.ingested.reagent_list.len >= 1)
		for(var/datum/reagent/R in H.ingested.reagent_list)
			// Apply the same scan_level gate to ingested — was missing
			// entirely, leaking unscannable chems via the ingested list.
			if(R.scannable > scan_level)
				continue
			ingestedData += list(list(
				"name"     = R.name,
				"amount"   = R.volume,
				"overdose" = (R.overdose && R.volume > R.overdose) ? TRUE : FALSE,
			))
	out["ingested"] = length(ingestedData) ? ingestedData : null


/// The scanner's prosthesis label for an internal organ (D7: the robotic LEVEL is compared,
/// not a bit of the status bitfield that happened to share ORGAN_ASSISTED's value).
/proc/bodyscanner_organ_kind(obj/item/organ/I)
	if(I.robotic == ORGAN_ASSISTED)
		return "Assisted"
	if(I.is_robotic())
		return "Mechanical"
	return null
