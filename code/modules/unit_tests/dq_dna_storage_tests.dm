/**
 * Parity tests for the /datum/dna storage compaction (doc/rewrite/memory_lists_audit.md).
 *
 * uni_identity/struc_enzymes used to be materialized strings kept in permanent
 * sync with the SE[93]/UI[65] block arrays (i.e. every DNA datum carried its
 * genetic data twice). They are now derived on demand via GetUniIdentity()/
 * GetStrucEnzymes(), with SetUniIdentity()/SetStrucEnzymes() as the inverse.
 * SE/UI block access itself (GetSEValue/SetSEValue/GetSEState/SetSEState/
 * GetUIValue/SetUIValue) is untouched -- these tests make sure that stays true.
 */

/// Encoding a DNA datum's UI/SE state to hex and decoding it back must reproduce
/// the exact same per-block values.
/datum/unit_test/dq_dna_encode_decode_roundtrip

/datum/unit_test/dq_dna_encode_decode_roundtrip/Run()
	var/datum/dna/D = new()
	for(var/i = 1 to DNA_SE_LENGTH)
		D.SetSEValue(i, (i * 37) % 4096, 1)
	for(var/i = 1 to DNA_UI_LENGTH)
		D.SetUIValue(i, (i * 61) % 4096, 1)

	var/se_hex = D.GetStrucEnzymes()
	var/ui_hex = D.GetUniIdentity()
	TEST_ASSERT_EQUAL(length(se_hex), 3 * DNA_SE_LENGTH, "encoded SE hex string should be 3 chars per block")
	TEST_ASSERT_EQUAL(length(ui_hex), 3 * DNA_UI_LENGTH, "encoded UI hex string should be 3 chars per block")

	// Decode into a fresh datum and check every block matches.
	var/datum/dna/D2 = new()
	D2.SetStrucEnzymes(se_hex)
	D2.SetUniIdentity(ui_hex)

	for(var/i = 1 to DNA_SE_LENGTH)
		TEST_ASSERT_EQUAL(D2.GetSEValue(i), D.GetSEValue(i), "SE block [i] should round-trip through hex encode/decode")
	for(var/i = 1 to DNA_UI_LENGTH)
		TEST_ASSERT_EQUAL(D2.GetUIValue(i), D.GetUIValue(i), "UI block [i] should round-trip through hex encode/decode")

	// And the re-encoded strings should match byte for byte.
	TEST_ASSERT_EQUAL(D2.GetStrucEnzymes(), se_hex, "re-encoding a round-tripped SE state should reproduce the same hex string")
	TEST_ASSERT_EQUAL(D2.GetUniIdentity(), ui_hex, "re-encoding a round-tripped UI state should reproduce the same hex string")

	qdel(D)
	qdel(D2)

/// GetSEState()/SetSEState() (what domutcheck() reads to decide if a gene is
/// active) must behave identically after the storage compaction: toggling one
/// block's on/off state must not disturb any other block.
/datum/unit_test/dq_dna_se_state_toggle_independent

/datum/unit_test/dq_dna_se_state_toggle_independent/Run()
	var/datum/dna/D = new()
	D.ResetSE()
	TEST_ASSERT(D.dna_ready, "ResetSE() should mark the dna datum ready")

	var/list/before = list()
	for(var/i = 1 to DNA_SE_LENGTH)
		before += D.GetSEState(i)

	// Force block 5 on and block 6 off, regardless of their rolled state.
	D.SetSEState(5, TRUE)
	D.SetSEState(6, FALSE)
	TEST_ASSERT(D.GetSEState(5), "SetSEState(block, TRUE) should read back as active")
	TEST_ASSERT(!D.GetSEState(6), "SetSEState(block, FALSE) should read back as inactive")

	// Every other block's on/off state should be untouched.
	for(var/i = 1 to DNA_SE_LENGTH)
		if(i == 5 || i == 6)
			continue
		TEST_ASSERT_EQUAL(D.GetSEState(i), before[i], "toggling blocks 5/6 should not change block [i]'s state")

	qdel(D)

/// Clone() must produce a DNA datum whose encoded identity, enzymes and
/// cosmetic/species vars are all identical to the source -- this is what
/// backs cloning and resleeving copying a character's genetics faithfully.
/datum/unit_test/dq_dna_clone_is_identical

/datum/unit_test/dq_dna_clone_is_identical/Run()
	var/datum/dna/D = new()
	D.ResetUI()
	D.ResetSE()
	D.unique_enzymes = md5("dq_dna_clone_is_identical")
	D.real_name = "Test Clone Source"
	D.custom_heat = list("It's warm.")
	D.custom_cold = list("It's cold.")
	D.species_traits = list("test_trait")

	var/datum/dna/clone = D.Clone()

	TEST_ASSERT_EQUAL(clone.GetStrucEnzymes(), D.GetStrucEnzymes(), "a clone's SE block state should match the source exactly")
	TEST_ASSERT_EQUAL(clone.GetUniIdentity(), D.GetUniIdentity(), "a clone's UI block state should match the source exactly")
	TEST_ASSERT_EQUAL(clone.unique_enzymes, D.unique_enzymes, "a clone should keep the same unique_enzymes")
	TEST_ASSERT_EQUAL(clone.real_name, D.real_name, "a clone should keep the same real_name")
	TEST_ASSERT(clone.dna_ready, "a clone of a ready dna datum should also be ready")

	// Lists must be copied, not shared by reference (mutating the clone must not
	// affect the source).
	TEST_ASSERT(clone.custom_heat != D.custom_heat, "clone.custom_heat should be a distinct list instance")
	clone.custom_heat += "New line."
	TEST_ASSERT_EQUAL(length(D.custom_heat), 1, "mutating the clone's custom_heat should not affect the source")

	qdel(D)
	qdel(clone)

/// A freshly created, unattached dna datum (no mob) is not "ready" until
/// check_integrity() gives it its backwards-compat default identity -- this is
/// what dna_modifier.dm's occupant buffer panel and similar UIs rely on when
/// they read GetUniIdentity()/GetStrucEnzymes() off a detached dna datum.
/datum/unit_test/dq_dna_check_integrity_detached_default

/datum/unit_test/dq_dna_check_integrity_detached_default/Run()
	var/datum/dna/D = new()
	TEST_ASSERT(!D.dna_ready, "a freshly created dna datum should not be ready yet")

	D.check_integrity()
	TEST_ASSERT(D.dna_ready, "check_integrity() on a detached dna datum should make it ready")
	TEST_ASSERT_EQUAL(length(D.GetUniIdentity()), 3 * DNA_UI_LENGTH, "the detached default UI identity should be fully populated")
	TEST_ASSERT_EQUAL(length(D.GetStrucEnzymes()), 3 * DNA_SE_LENGTH, "the detached default SE state should be fully populated")

	// Calling it again must not change anything (idempotent, matches old
	// "already the right length, skip" behaviour).
	var/first_ui = D.GetUniIdentity()
	var/first_se = D.GetStrucEnzymes()
	D.check_integrity()
	TEST_ASSERT_EQUAL(D.GetUniIdentity(), first_ui, "check_integrity() should be idempotent for UI once ready")
	TEST_ASSERT_EQUAL(D.GetStrucEnzymes(), first_se, "check_integrity() should be idempotent for SE once ready")

	qdel(D)
