/// Real keyed body-record retirement and its owned DNA, without transcore-system substitution.
/datum/unit_test/round2_transcore_body_record_retirement/Run()
	test_driver_begin()
	exercise_records()
	test_driver_end()

/datum/unit_test/round2_transcore_body_record_retirement/proc/exercise_records()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/donor = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	donor.fully_replace_character_name(null, "Retirement donor")
	other.fully_replace_character_name(null, "Independent donor")
	var/datum/transcore_db/db = allocate(/datum/transcore_db)
	var/datum/transhuman/body_record/record = allocate(/datum/transhuman/body_record, donor, FALSE, FALSE)
	var/datum/transhuman/body_record/control = allocate(/datum/transhuman/body_record, other, FALSE, FALSE)
	var/datum/transhuman/body_record/missing = allocate(/datum/transhuman/body_record, donor, FALSE, FALSE)
	var/datum/dna2/record/original_dna = record.mydna
	var/datum/dna/original_genome = original_dna?.dna
	var/datum/dna2/record/control_dna = control.mydna
	var/datum/dna/control_genome = control_dna?.dna
	TEST_ASSERT(original_dna && original_genome && control_dna && control_genome, "actual human-backed constructors produce complete owned DNA")
	TEST_ASSERT(original_genome != donor.dna && control_genome != other.dna, "actual records own distinct cloned genomes")
	var/record_key = original_dna.name
	var/control_key = control_dna.name
	TEST_ASSERT(record_key != control_key, "actual donor naming yields independent real keys")
	db.add_body(record)
	db.add_body(control)
	TEST_ASSERT_EQUAL(db.body_scans[record_key], record, "sole public producer registers the exact first record")
	TEST_ASSERT_EQUAL(db.body_scans[control_key], control, "sole public producer registers the exact independent record")
	db.remove_body(record)
	TEST_ASSERT(QDELETED(record), "real removal retires the exact registered original record")
	TEST_ASSERT(QDELETED(original_dna) && QDELETED(original_genome), "record teardown retires its exact original owned DNA and genome")
	TEST_ASSERT(!(record_key in db.body_scans), "real removal drops only the exact original registry key")
	TEST_ASSERT_EQUAL(db.body_scans[control_key], control, "unrelated exact record remains registered")
	TEST_ASSERT(!QDELETED(control) && control.mydna == control_dna && control_dna.dna == control_genome, "independent original DNA identities remain alive")
	db.remove_body(missing)
	db.remove_body(missing)
	TEST_ASSERT(!QDELETED(missing) && missing.mydna, "repeated missing-key removal does not delete an unregistered live constructor result")
	TEST_ASSERT_EQUAL(length(db.body_scans), 1, "repeated missing-key removal preserves the sole independent entry")
	TEST_ASSERT_EQUAL(db.body_scans[control_key], control, "missing-key calls leave the exact independent original registered")
	TEST_ASSERT(!QDELETED(donor.dna) && !QDELETED(other.dna), "record retirement preserves both actual donor genomes")
