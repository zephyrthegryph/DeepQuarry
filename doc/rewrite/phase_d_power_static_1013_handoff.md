# Static power moves — 2026-10-13

Branch: codex/phase-d-power-static-1013. Lane-ready tested/stamped 281a4df253bc on master 58d9773d2c; this handoff is a documentation-only child under agent_workflow section 14.

Moved lighting_neon.dm and tesla/generator.dm from code/modules/power into code/domains/power/content, as allowed by final_api section 22's power model/content split. Both moves are R100 with zero source edits; two DME paths changed without changing include order. Their current-master blobs and recent history were checked before moving. No active source overlap was found.

Verification: 52 passed, zero failed. Production compile zero errors, DreamChecker zero diagnostics, ratchets/analyze passed. Includes dq_requirement_protocol_pin, dq_conversion_pin, incremental appearance pins, and concrete tube/small lighting fixture tests. The light tests cover shared fixture construction, not direct neon/Tesla subtype interactions. No baseline increase, ALLOW, pin blessing, Rust build, full suite or second lane test world was introduced.

No player-visible behavior change is intended. The old prepared codex/phase-d-power-static-1012 branch was left untouched; this fresh branch carries only the two moves, include updates and this handoff.
