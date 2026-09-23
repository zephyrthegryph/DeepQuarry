// Scratch focus file for fast local/CI iteration — KEEP EMPTY IN COMMITS.
//
// To run only specific tests (skipping the ~40-minute full suite), add lines
// like the following and rebuild; RunUnitTests() then runs only focused tests:
//
//     TEST_FOCUS(/datum/unit_test/dq_expedition_generates_site)
//     TEST_FOCUS(/datum/unit_test/dq_human_deletion_destroys_all_organs)

//
// Automation may append lines here on a build host for a minimal run; nothing
// in this file should ever be committed non-empty (CI runs the full suite).
TEST_FOCUS(/datum/unit_test/dq_armor_interning)
TEST_FOCUS(/datum/unit_test/dq_armor_specs_parse)
TEST_FOCUS(/datum/unit_test/dq_armor_mitigation_table)
TEST_FOCUS(/datum/unit_test/dq_armor_parity_with_old_roll)
TEST_FOCUS(/datum/unit_test/dq_armor_sharp_to_blunt)
TEST_FOCUS(/datum/unit_test/dq_armor_worn_cache_combines)
TEST_FOCUS(/datum/unit_test/dq_armor_object_mitigation)
TEST_FOCUS(/datum/unit_test/dq_armor_material_response)
TEST_FOCUS(/datum/unit_test/dq_armor_shield_blocks)
TEST_FOCUS(/datum/unit_test/dq_harm_kind_declarations)
TEST_FOCUS(/datum/unit_test/dq_harm_armor_by_kind)
TEST_FOCUS(/datum/unit_test/dq_harm_mitigation_pipeline)
TEST_FOCUS(/datum/unit_test/dq_harm_object_damage_derived)
