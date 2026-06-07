// Body scanner data builder.
//
// Replaces the upstream /obj/machinery/bodyscanner/tgui_data block. The
// shape is intentionally reduced from the old version:
//
//   - Per-damage-type numbers (bruteLoss / oxyLoss / etc.) become a
//     qualitative `damagePanel` array — one band per damage type.
//   - Per-organ raw damage values are gone. Each organ emits an
//     `injuryBand` qualitative string instead.
//   - The grab-bag `medical_issues_E` / `medical_issues_I` lists (which
//     dumped every active condition's name) are gone. The TGUI gets a
//     deduplicated `scanner_findings` array derived from active symptoms
//     whose audiences flag includes SYMPTOM_AUDIENCE_SCANNER.
//
// What survives unchanged: name / species / blood / reagents / ingested /
// allergens / abnormality flags / implants / discrete organ states
// (broken, bleeding, splinted, robotic, dead, missing, lungRuptured,
// inflamed appendix, internal bleeding).

/obj/machinery/bodyscanner/proc/dq_build_tgui_data()
	var/list/data = list()
	data["occupied"] = occupant ? TRUE : FALSE

	if(!(occupant && ishuman(occupant)))
		data["occupant"] = list()
		return data

	update_icon()
	var/mob/living/carbon/human/H = occupant
	var/list/occupantData = list()

	dq_emit_identity(H, occupantData)
	dq_emit_status(H, occupantData)
	dq_emit_vitals(H, occupantData)
	dq_emit_abnormalities(H, occupantData)
	dq_emit_reagents(H, occupantData)
	dq_emit_external_organs(H, occupantData)
	dq_emit_internal_organs(H, occupantData)

	// Scanner-detected DQ findings: dedup by (organ + phrase), then sort
	// most-severe first so triage reads top-down. The Condition row on
	// the occupant card escalates to match the worst finding so a medic
	// glancing at the patient gets the urgency before reading details.
	var/list/findings = dq_qualitative_scanner_findings(H)
	var/list/seen = list()
	// Bucket findings by severity band so the emit is sorted without
	// an in-place comparator over nested lists (DM list.Insert can't
	// reliably splice a list-of-lists by index).
	var/list/by_band = list("critical" = list(), "severe" = list(), "moderate" = list(), "minor" = list(), "uninjured" = list())
	var/worst = "uninjured"
	for(var/list/f in findings)
		var/key = "[f["organ"]]||[f["phrase"]]"
		if(seen[key])
			continue
		seen[key] = TRUE
		var/band = f["severity"] || "minor"
		if(!by_band[band])
			by_band[band] = list()
		by_band[band] += list(f)
		if(_dq_band_rank(band) > _dq_band_rank(worst))
			worst = band
	var/list/finding_out = list()
	for(var/band in list("critical", "severe", "moderate", "minor", "uninjured"))
		for(var/list/entry in by_band[band])
			finding_out += list(entry)
	occupantData["scannerFindings"] = finding_out
	occupantData["worstFinding"] = worst

	// Whole-body qualitative damage panel.
	occupantData["damagePanel"] = dq_qualitative_damage_panel(H)

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
	out["healthBand"] = fakedeath ? "critical" : dq_qualitative_health_band(H.health, H.getMaxHealth())


/obj/machinery/bodyscanner/proc/dq_emit_vitals(mob/living/carbon/human/H, list/out)
	out["bodyTempC"] = H.bodytemperature - T0C
	out["bodyTempF"] = (((H.bodytemperature - T0C) * 1.8) + 32)
	out["paralysisSeconds"] = round(H.paralysis / 4)

	var/list/bloodData = list()
	if(H.vessel)
		var/blood_volume = round(H.vessel.get_reagent_amount(REAGENT_ID_BLOOD))
		var/blood_max = H.species.blood_volume
		bloodData["volume"] = blood_volume
		bloodData["percent"] = blood_max ? round(((blood_volume / blood_max) * 100)) : 0
	out["blood"] = bloodData


/obj/machinery/bodyscanner/proc/dq_emit_abnormalities(mob/living/carbon/human/H, list/out)
	out["hasVirus"] = H.isInfective()
	out["hasBorer"] = H.has_brain_worms()
	out["blind"] = (H.sdisabilities & BLIND)
	out["nearsighted"] = (H.disabilities & NEARSIGHTED)
	out["brokenspine"] = (H.disabilities & SPINE)
	out["husked"] = (HUSK in H.mutations)

	var/has_withdrawl = FALSE
	for(var/addic in H.get_all_addictions())
		var/level = H.get_addiction_to_reagent(addic)
		if(level > 0 && level < 80)
			has_withdrawl = TRUE
			break
	out["hasWithdrawl"] = has_withdrawl

	out["allergens"] = assembly_allergy_list(H.species.allergens, H.species.medallergens)
	out["hasAllergens"] = islist(out["allergens"])

	out["colourblind"] = null
	for(var/datum/modifier/M in H.modifiers)
		if(!isnull(M.wire_colors_replace))
			out["colourblind"] = LAZYLEN(M.wire_colors_replace)
			break


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


/obj/machinery/bodyscanner/proc/dq_emit_external_organs(mob/living/carbon/human/H, list/out)
	var/list/extOrganData = list()
	for(var/obj/item/organ/external/E in H.organs)
		var/list/od = list()
		od["name"] = E.name
		od["open"] = E.open
		od["germ_level"] = E.germ_level
		od["injuryBand"] = dq_qualitative_damage_band(E.brute_dam + E.burn_dam, E.max_damage)
		od["hasBrute"] = E.brute_dam > 0
		od["hasBurn"] = E.burn_dam > 0

		var/list/implantData = list()
		for(var/obj/thing in E.implants)
			var/obj/item/implant/I = thing
			var/obj/item/nif/N = thing
			if(istype(I))
				implantData += list(list("name" = I.name, "known" = I.known_implant))
			else
				implantData += list(list("name" = N.name, "known" = N.known_implant))
		od["implants"] = implantData
		od["implants_len"] = implantData.len

		var/list/organStatus = list()
		if(E.status & ORGAN_DESTROYED)
			organStatus["destroyed"] = 1
		if(E.status & ORGAN_BROKEN)
			organStatus["broken"] = E.broken_description
		if(E.robotic >= ORGAN_ROBOT)
			organStatus["robotic"] = 1
		if(E.splinted)
			organStatus["splinted"] = 1
		if(E.status & ORGAN_BLEEDING)
			organStatus["bleeding"] = 1
		if(E.status & ORGAN_DEAD)
			organStatus["dead"] = 1
		od["status"] = organStatus

		if(istype(E, /obj/item/organ/external/chest) && H.is_lung_ruptured())
			od["lungRuptured"] = 1

		for(var/datum/wound/W in E.wounds)
			if(W.internal)
				od["internalBleeding"] = 1
				break

		extOrganData += list(od)
	out["extOrgan"] = extOrganData


/obj/machinery/bodyscanner/proc/dq_emit_internal_organs(mob/living/carbon/human/H, list/out)
	var/list/intOrganData = list()
	var/fakedeath = (H.status_flags & FAKEDEATH)

	for(var/organ_tag in H.species.has_organ)
		var/obj/item/organ/O = H.species.has_organ[organ_tag]
		var/name = initial(O.name)
		O = H.internal_organs_by_name[organ_tag]
		if(!O)
			intOrganData += list(list("name" = name, "missing" = TRUE))

	for(var/obj/item/organ/I in H.internal_organs)
		var/list/od = list()
		od["name"] = I.name
		if(I.status & ORGAN_ASSISTED)
			od["desc"] = "Assisted"
		else if(I.robotic >= ORGAN_ROBOT)
			od["desc"] = "Mechanical"
		od["germ_level"] = I.germ_level
		var/effective_damage = I.damage
		if(fakedeath)
			if(istype(I, /obj/item/organ/internal/brain))
				effective_damage = 200
			else if(istype(I, /obj/item/organ/internal/lungs))
				effective_damage = 25
		od["injuryBand"] = dq_qualitative_damage_band(effective_damage, I.max_damage)
		od["robotic"] = (I.robotic >= ORGAN_ROBOT) ? 1 : 0
		od["dead"] = (I.status & ORGAN_DEAD) ? 1 : 0
		if(istype(I, /obj/item/organ/internal/appendix))
			var/obj/item/organ/internal/appendix/A = I
			od["inflamed"] = A.inflamed
		intOrganData += list(od)
	out["intOrgan"] = intOrganData
