# Requirement burn-down D, 2026-10-10

Branch: `codex/requirements-zero-1010-d`. Starts from the preceding C branch's 425 requirement_bool fingerprints. This branch removes 117: storage/food/hydroponics 40; machinery/power 48; atmos 17; admin player effects 12. The merge of master `6db15e7005` removes another two, leaving 306. The baseline updater added no fingerprints.

Callbacks return null or their original refusal; separate refusal helpers were merged. Complete subtype overrides and non-requirement Boolean consumers were audited together. Genuine Boolean selection predicates remain selection predicates. Legacy equipment/rules consumers were not converted by changing tokens. No ALLOW was added, no baseline or ceiling raised, and no resolver/keybinding changes were made.

39 missing old-code type pins were recorded before production conversion, alongside existing pins. The 12-test old-code batch passed 11 tests; its tray fixture incorrectly assumed the legacy actor helper checked consciousness/paralysis. INCAPACITATION_DEFAULT actually checks restraint/full buckling. The fixture was corrected to exercise living/nonliving actor refusal and recovery; the failure-only repair passed 1/1 with a clean boot. No snapshot re-bless was needed for that repair.

`dq_medpod/sleeper_refusals` now saves/restores `GLOB.coalesce_runs` using unit-test teardown. It passed the old-code focused batch without a STATE LEAK. The new boundary tests exercise actual compiled requirements, including exact refusal messages, state changes, and recovery for tape, trays, botany, seed storage, bees, honey extraction, machines, and admin target types. Connected-ghost harvest success remains untested because it requires genuine client/eligibility state; the clientless pin is not claimed as that proof.

Master merge conflicts preserved `lets_go_of_held()` for closets, robotics' declared stopbot actor gate, and communications' declared newalertlevel actor gate, together with null-or-reason callbacks. Baselines were regenerated from the existing shrinking baseline rather than hand-unioned. The pure refusal-value normalizer now declares no world reads for generation.

Equipment-fit and simulation-rule protocols are proposed in `doc/requirement_consumer_protocol_proposal_1010.md`. The proposal specifies acceptance context, ordered refusal semantics, inherited/instance overrides, tracked dependencies, unit-aware comparison/threshold metadata and edge-trigger parity. Those tables require consumer migration before conversion; no proposed form is implemented here.

The next audit identifies 118 candidate fingerprints across 60 files, with ten semantic samples and inherited/cross-file traps. Machinery remote/display rows remain excluded pending the resolver owner. The preceding C branch's AI Equip-click pin has not been blessed or edited here.

Lane-ready passed on `d57231178e8d3b65ec2b56873e2916d387e17bed`, merged against master `6db15e7005`: stamp reports 88 passed, 0 failed. Production compile: 0 errors (43 existing DreamMaker warnings); DreamChecker: 0 diagnostics; ratchets: all passed; boot gate: clean. Evidence: `data/test-runs/20261010T212040_d57231178e_focused.json` and `data/merge-gates/d57231178e8d.{dm,tests,ratchets}.log`. No conversion pin changed after the old-code capture. Incremental look selection had zero changed types; no full look sweep was run.

Additional warnings in the combined smoke run: `dq_construction_floor` leaves coalesce_runs, `dq_atmos_m/canister_welder` initializes test_prompts, and sleeper_refusals initializes the separate lazy status_policies cache. The requested sleeper coalesce_runs leak no longer appears. These warnings were not represented as failing assertions by the runner and remain reported rather than hidden.
