// Medical access and diagnosis: the treatment items a medic needs are obtainable, the encyclopedia is in medbay, the basic analyzer reads
// the vitals-level signs of what it can't image, and every treatment mechanism has analyzer guidance.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Every item type held in `container` (and in anything it holds), as a list of types.
/datum/unit_test/proc/dq_access_held_types(atom/container)
	. = list()
	for(var/obj/item/I in container.contents)
		. += I.type
		. += dq_access_held_types(I)

/// The treatment items that once had no spawn path.
/datum/unit_test/dq_medical_items_obtainable

/datum/unit_test/dq_medical_items_obtainable/Run()
	var/list/wanted = list(
		/obj/item/decompression_needle, /obj/item/airway_kit, /obj/item/bag_valve_mask, /obj/item/tourniquet,
		/obj/item/stack/medical/field/chest_seal, /obj/item/stack/medical/field/hemostatic_gauze, /obj/item/stack/medical/field/pressure_bandage,
		/obj/item/reagent_containers/hypospray/autoinjector/stabiliser, /obj/item/storage/firstaid/stabilisation,
		/obj/item/pulse_oximeter, /obj/item/bp_cuff, /obj/item/thermometer_medical,
	)
	var/list/kits = list(/obj/item/storage/firstaid/stabilisation, /obj/item/storage/firstaid/resuscitation, /obj/item/storage/firstaid/diagnostic)
	// The kits spawn holding them...
	var/list/in_kits = list()
	for(var/kit_type in kits)
		var/obj/item/storage/kit = allocate(kit_type, dq_containment_floor())
		in_kits += kit_type
		in_kits += dq_access_held_types(kit)
	for(var/item_type in wanted)
		TEST_ASSERT(item_type in in_kits, "[item_type] is not in any spawned kit")
	// ...and medbay lockers stock the kits.
	var/list/stocked = list()
	for(var/locker_type in list(/obj/structure/closet/secure_closet/medical1, /obj/structure/closet/secure_closet/medical3, /obj/structure/closet/secure_closet/paramedic, /obj/structure/closet/secure_closet/chief_medical_officer))
		var/obj/structure/closet/secure_closet/locker = allocate(locker_type, dq_containment_floor())
		for(var/obj/item/I in locker.contents)
			stocked += I.type
	for(var/kit_type in kits)
		TEST_ASSERT(kit_type in stocked, "no medbay locker stocks [kit_type]")

/// The Doctor's Encyclopedia is in medbay: the medical bookcase, the CMO's locker, the library archive.
/datum/unit_test/dq_medical_encyclopedia_exists

/datum/unit_test/dq_medical_encyclopedia_exists/Run()
	var/obj/structure/bookcase/manuals/medical/shelf = allocate(/obj/structure/bookcase/manuals/medical, dq_containment_floor())
	TEST_ASSERT(/obj/item/book/dq_medical_reference in dq_access_held_types(shelf), "the medical bookcase does not hold the Doctor's Encyclopedia")
	var/obj/structure/closet/secure_closet/chief_medical_officer/locker = allocate(/obj/structure/closet/secure_closet/chief_medical_officer, dq_containment_floor())
	TEST_ASSERT(/obj/item/book/dq_medical_reference in dq_access_held_types(locker), "the CMO locker does not stock the Doctor's Encyclopedia")
	var/obj/machinery/librarycomp/comp = allocate(/obj/machinery/librarycomp, dq_containment_floor())
	var/list/archive = comp.build_all_books()
	var/found = FALSE
	for(var/book_name in archive)
		var/list/row = archive[book_name]
		if(row["path"] == "[/obj/item/book/dq_medical_reference]")
			found = TRUE
	TEST_ASSERT(found, "the library archive does not offer the Doctor's Encyclopedia")

/// The basic analyzer reports shock, sepsis, a fracture and internal bleeding on a patient who has them, by sign and not by name.
/datum/unit_test/dq_basic_analyzer_reads_signs

/datum/unit_test/dq_basic_analyzer_reads_signs/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	TEST_ASSERT_NOTNULL(H.body.afflict(/datum/affliction/hypovolemic_shock, H.get_organ(BP_TORSO), 60), "shock could not be afflicted")
	TEST_ASSERT_NOTNULL(H.body.afflict(/datum/affliction/sepsis, null, 60), "sepsis could not be afflicted")
	TEST_ASSERT_NOTNULL(H.body.afflict(/datum/affliction/untreated_fracture, H.get_organ(BP_L_LEG), 60), "a fracture could not be afflicted")
	TEST_ASSERT_NOTNULL(H.body.afflict(/datum/affliction/internal_hemorrhage, H.get_organ(BP_TORSO), 60), "internal bleeding could not be afflicted")
	var/datum/diagnosis/basic = H.diagnose(/datum/diagnostic_profile/health_analyzer)
	var/datum/diagnosis/advanced = H.diagnose(/datum/diagnostic_profile/health_analyzer/advanced)
	var/list/names = list()
	for(var/datum/diagnosis_finding/F as anything in basic.findings)
		names += F.name
	for(var/sign in list("shock", "fever, infection suspected", "suspected fracture", "suspected internal bleeding"))
		TEST_ASSERT(sign in names, "the basic analyzer did not report '[sign]' (reported: [jointext(names, "; ")])")
	// A sign is not the condition: the name and the lab detail stay with the tools that image it.
	TEST_ASSERT(!basic.has_finding_for(/datum/affliction/sepsis), "the basic analyzer should report a sign, not name sepsis")
	TEST_ASSERT(advanced.has_finding_for(/datum/affliction/sepsis), "the advanced analyzer should name sepsis")
	qdel(basic)
	qdel(advanced)

/// An organ lesion reads as organ damage by organ; sepsis shows on examine.
/datum/unit_test/dq_basic_analyzer_reads_organ_and_fever

/datum/unit_test/dq_basic_analyzer_reads_organ_and_fever/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/organ/internal/liver = H.organ_in(O_LIVER)
	H.injure(INJURY_BLUNT, liver.max_damage * 0.5, liver, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	var/datum/diagnosis/basic = H.diagnose(/datum/diagnostic_profile/health_analyzer)
	var/found = FALSE
	for(var/datum/diagnosis_finding/F as anything in basic.findings)
		if(findtext(F.name, "organ damage") && findtext(F.name, "liver"))
			found = TRUE
	TEST_ASSERT(found, "the basic analyzer did not flag organ damage by organ")
	qdel(basic)
	TEST_ASSERT_NOTNULL(H.body.afflict(/datum/affliction/sepsis, null, 60), "sepsis could not be afflicted")
	var/datum/diagnosis/glance = H.diagnose(/datum/diagnostic_profile/glance)
	var/visible = FALSE
	for(var/line in glance.examine_lines())
		if(findtext(line, "feverish"))
			visible = TRUE
	TEST_ASSERT(visible, "sepsis should show on examine: pale or flushed and feverish")
	qdel(glance)

/// Every TREAT_* mechanism has a guidance line, and so does every tag a catalogued condition lists.
/datum/unit_test/dq_analyzer_guidance_covers_every_tag

/datum/unit_test/dq_analyzer_guidance_covers_every_tag/Run()
	var/list/tags = list(
		TREAT_HEMOSTATIC, TREAT_TISSUE_REPAIR, TREAT_BONE_REPAIR, TREAT_BURN_CARE, TREAT_ANTIMICROBIAL, TREAT_ANTITOXIN, TREAT_OXYGENATION,
		TREAT_NEURAL_REPAIR, TREAT_CARDIAC, TREAT_RESPIRATORY, TREAT_HEPATORENAL, TREAT_OCULAR, TREAT_ANTIRADIATION, TREAT_GENETIC_REPAIR,
		TREAT_THERMOREGULATION, TREAT_BLOOD_RESTORE, TREAT_CIRCULATORY, TREAT_ANALGESIC, TREAT_STIMULANT, TREAT_PLATING_REPAIR,
		TREAT_WIRING_REPAIR, TREAT_SYSTEM_RESTORE, TREAT_COOLANT, TREAT_CALIBRATION, TREAT_SURGICAL_REPAIR, TREAT_RESECTION, TREAT_AIRWAY,
		TREAT_DECOMPRESSION, TREAT_DEFIBRILLATION, TREAT_CHEST_COMPRESSION, TREAT_VASOPRESSOR, TREAT_DIGESTIVE, TREAT_ANTIEMETIC,
		TREAT_ANTICONVULSANT, TREAT_WOUND_PACKING, TREAT_OCCLUSIVE_SEAL, TREAT_REGENERATION, TREAT_RESTORATION, TREAT_FEEDSTOCK,
		TREAT_SURGICAL_CLOSURE, TREAT_PANEL_CLOSURE, TREAT_BONE_SETTING, TREAT_VESSEL_REPAIR, TREAT_TENDON_REPAIR, TREAT_FOREIGN_BODY_REMOVAL,
		TREAT_LITHOTRIPSY, TREAT_BURN_DEEP, TREAT_ANTIEDEMA, TREAT_SOULMEND, TREAT_OPIOID_ANTAGONIST,
	)
	for(var/path in subtypesof(/datum/affliction))
		var/datum/affliction/typed = path
		if(!initial(typed.catalogued))
			continue
		var/datum/affliction/proto = dq_proto(path)
		for(var/tag in proto.treated_by)
			TEST_ASSERT(analyzer_guidance_line(tag), "[path] lists treatment tag [tag] with no analyzer guidance")
	for(var/tag in tags)
		TEST_ASSERT(analyzer_guidance_line(tag), "treatment tag [tag] has no analyzer guidance")
	TEST_ASSERT_EQUAL(length(GLOB.analyzer_guidance), length(tags), "the guidance table and the tag list disagree")

#endif
