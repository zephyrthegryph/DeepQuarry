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
TEST_FOCUS(/datum/unit_test/dq_rule_compile)
TEST_FOCUS(/datum/unit_test/dq_rule_thresholds)
TEST_FOCUS(/datum/unit_test/dq_rule_subscription)
TEST_FOCUS(/datum/unit_test/dq_rule_hold_and_band)
TEST_FOCUS(/datum/unit_test/dq_rule_paper_ignition)
TEST_FOCUS(/datum/unit_test/dq_rule_plastic_melts)
TEST_FOCUS(/datum/unit_test/dq_rule_grille_parity)
TEST_FOCUS(/datum/unit_test/dq_property_registry_validates)
