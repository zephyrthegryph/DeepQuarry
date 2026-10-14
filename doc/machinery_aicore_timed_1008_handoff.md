# AIcore timed construction handoff (2026-10-08)

Branch: codex/machinery-audit-1008. Old-code pin commit e6e9a6b5a3 is already pushed and included in this branch.

Converted all five AIcore use_tool waits to native tool operations: base anchor, unanchor and dismantle; deactivated bolt and unbolt. use_tool sites in ai_core.dm: 5 -> 0. The file was already in timed_forms_converted, so no new ban was needed. Real clicks now reach these construction paths instead of the generic item catch-all. Tool speed, skill scaling, cancellation, state, custody, start sounds and exact four-plasteel refund are retained.

The shared fuel adapter now resolves get_welder() for availability, reservation ownership and commit, fixing transforming-tool commits. Seven native asks preparation handlers take datum/act/op directly; their only callers provide that context. No lint exemption, ceiling increase, legacy-call rename or ALLOW was introduced. Baseline files are unchanged after baseline --update.

Old-code verification: 34 passed, zero failures/skips, before converting production source (see machinery_last_timed_1008_old_pin_report.md and provenance JSON).

Final verification: one test compile, zero errors and 50 existing warnings; 32 focused tests passed, zero failures/skips, clean boot and no leaks. Result: data/test-runs/20261008T175201_c482089230.json. Includes completion/drop/movement for each path, five fast-tool variants, real transforming-tool dismantling, wrapped fuel reservation/consumption, existing cable/glass construction, and four native prompt regressions. No full suite or shards ran. Fresh lint passed with DreamChecker zero diagnostics; fresh ratchets passed. Logs: data/codex-machinery/last-timed-1008/aicore-final-lint.log, aicore-final-ratchets.log and aicore-focused.log.

Reviewed pin changes: AIcore scoped pin and identical canonical pin each have five added and three removed rows, exposing Anchor frame and Dismantle frame clicks plus native operation keys. Per-class causes for base and deactivated AIcore are in doc/rewrite/intended_changes.md. Kiosk, cryopod and cycler scoped pins remain byte-identical.

Pending: medical kiosk claims during questions, cryopod passenger answerer and cycler starts refusal remain unapplied drafts. No work was based on rewrite/notices-asks. Last fetch: origin/master d08acc96b9 does not contain e03f6c58d6 yet, so the batch-13 merge is pending. Merge with tools/dq_merge_master.sh after publication; apply the dependent drafts only once the user confirms the forms landed on master.
