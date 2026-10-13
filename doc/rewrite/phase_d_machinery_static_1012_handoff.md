# Static machinery moves — 2026-10-13

Branch: codex/phase-d-machinery-static-1012. Lane-ready tested and stamped 9ff91389f1fa on master 58d9773d2c; the handoff is a documentation-only child under agent_workflow section 14.

Six files moved from code/game/machinery to code/content/machinery: autolathe_armory.dm, computer/RCON_Console.dm, computer/shutoff_monitor.dm, computer/syndicate_specops_shuttle.dm, suit_storage/suit_storage_units.dm and suit_storage_unit.dm. Every move is R100: zero DM content edits. Six DME include paths changed in their existing order. Current-master source history was audited for overlap before the moves; none of these sources changed recently.

Verification: lane-ready passed 58 tests with zero failures; production compilation had zero errors, DreamChecker zero diagnostics, and ratchets/analyze passed with zero unused annotations. No baselines increased, no ALLOWs added, no pin rows blessed and no full suite run. The run includes dq_requirement_protocol_pin, dq_conversion_pin, incremental appearance pins, suit-storage occupancy/locking and timed entry/cancel/grab cases, plus RCON/shutoff button tests. The last two prove their existing button modules, not console click ranking.

Only file layout changed; no player-visible behavior change is intended. The separate machinery-channel, scalar memo and test-hygiene branches retain their documented analyzer-owner dependencies.
