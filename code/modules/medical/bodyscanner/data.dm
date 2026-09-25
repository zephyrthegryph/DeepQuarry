// Body scanner data builder.
//
// The patient's condition is the body scanner profile's diagnosis
// (code/modules/medical/diagnosis/): vitals, findings (conditions, lesions,
// wounds and presenting signs, with trends and hints) and per-limb bands,
// rendered by /datum/diagnosis/proc/report_data() into `diagnosis`.
//
// Alongside it: identity, abnormality flags, reagents, implants and the
// discrete organ states (broken, bleeding, splinted, robotic, dead, missing,
// lung rupture, internal bleeding).

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

	var/datum/diagnosis/D = H.diagnose(/datum/diagnostic_profile/body_scanner)
	occupantData["diagnosis"] = D.report_data()
	occupantData["healthBand"] = D.band
	occupantData["worstFinding"] = D.worst_finding_band()
	qdel(D)

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
	out["paralysisSeconds"] = round(H.status_seconds(EFFECT_PARALYZED))


/obj/machinery/bodyscanner/proc/dq_emit_abnormalities(mob/living/carbon/human/H, list/out)
	out["hasVirus"] = H.isInfective()
	out["hasBorer"] = H.has_brain_worms()
	out["blind"] = (H.sdisabilities & BLIND)
	out["nearsighted"] = (H.disabilities & NEARSIGHTED)
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
		od["injuryBand"] = dq_qualitative_damage_band(E.get_trauma() + E.get_burn(), E.max_damage)

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

		if(length(dq_limb_internal_bleeds(E)))
			od["internalBleeding"] = 1

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
