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
TEST_FOCUS(/datum/unit_test/dq_verdigris_loaded)
TEST_FOCUS(/datum/unit_test/dq_gas_mixture_rust_roundtrip)
TEST_FOCUS(/datum/unit_test/dq_turf_air_persistence)
TEST_FOCUS(/datum/unit_test/dq_plasmafire_reaction_consumes_plasma)
TEST_FOCUS(/datum/unit_test/dq_canister_release_to_turf)
TEST_FOCUS(/datum/unit_test/dq_phoron_spreads_to_adjacent_floor)
TEST_FOCUS(/datum/unit_test/dq_gas_equilibrates_over_ticks)
TEST_FOCUS(/datum/unit_test/dq_wall_blocks_gas_spread)
TEST_FOCUS(/datum/unit_test/dq_total_moles_conserved_long_run)
TEST_FOCUS(/datum/unit_test/dq_multiz_spread_through_open_turf)
TEST_FOCUS(/datum/unit_test/dq_planetary_atmos_converges_to_baseline)
TEST_FOCUS(/datum/unit_test/dq_gas_overlays_appear_on_share)
TEST_FOCUS(/datum/unit_test/dq_zair_blocks_vertical_through_floor)
TEST_FOCUS(/datum/unit_test/dq_floor_adjacency_lists_floor_neighbors)
TEST_FOCUS(/datum/unit_test/dq_power_cut_splits_and_repair_merges)
TEST_FOCUS(/datum/unit_test/dq_reactor_gas_watches)
TEST_FOCUS(/datum/unit_test/dq_phoron_renders_above_visible_threshold)
