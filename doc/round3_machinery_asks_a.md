# Round 3 machinery asks: slice A dispositions

Scope is the 28 original sites in 15 files assigned from the handoff appendix, not the global request inventory. Of these, 21 sites now use the existing op workflow, 5 obsolete jukebox sites are removed, and 2 paths retain explicit engine/entry-point gaps. No build, tests or lint have been run by this coding agent.

The record editors use a named text step and a conditional delete confirmation, with CANCEL_IF_CHANGED selection capture. The message monitor keeps both password answers in one workflow and captures the selected server. The other converted UI and hand inputs commit only after their questions finish. Existing prompt cancellation, spatial/capability flags and window checks stay in the framework. No new request wrapper, callback alias or duplicated CAPABILITIES block is introduced.

| Original file | Original line | Disposition |
|---|---:|---|
| `code/game/machinery/computer/arcade.dm` | 1176 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/computer/medical.dm` | 329 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/computer/message.dm` | 207 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/computer/message.dm` | 262 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/computer/message.dm` | 376 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/computer/message.dm` | 417 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/computer/security.dm` | 309 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/computer/skills.dm` | 747 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/food_replicator.dm` | 63 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/jukebox.dm` | 415 | Removed obsolete request chain: existing native VV ops already own this workflow. |
| `code/game/machinery/jukebox.dm` | 430 | Removed obsolete request chain: existing native VV ops already own this workflow. |
| `code/game/machinery/jukebox.dm` | 436 | Removed obsolete request chain: existing native VV ops already own this workflow. |
| `code/game/machinery/jukebox.dm` | 442 | Removed obsolete request chain: existing native VV ops already own this workflow. |
| `code/game/machinery/jukebox.dm` | 455 | Removed obsolete request chain: existing native VV ops already own this workflow. |
| `code/game/machinery/magnet.dm` | 269 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/medical_kiosk.dm` | 92 | OPEN: wake_lock/active_user ownership starts before the prompt; moving it after the answer changes busy/cancel semantics. |
| `code/game/machinery/newscaster.dm` | 418 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/newscaster.dm` | 427 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/newscaster.dm` | 432 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/newscaster.dm` | 437 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/newscaster.dm` | 494 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/newscaster.dm` | 504 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/painter.dm` | 191 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/pandemic.dm` | 161 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/pandemic.dm` | 171 | Migrated to the existing declared op's asks workflow. |
| `code/game/machinery/status_display_ai.dm` | 44 | OPEN: raw granted ai_statuschange verb has no native op binding; an imperative request wrapper would not be migration. |
| `code/game/machinery/telecomms/traffic_control.dm` | 102 | Migrated to the existing declared op's asks workflow. |
| `code/modules/power/cable.dm` | 941 | Migrated to the existing declared op's asks workflow. |

## Focused verification for the coordinator

Include `code/modules/unit_tests/round3_machinery_asks_a.dm` after the existing computer/struct fixture bases. New tests are `/datum/unit_test/dq_hc_computers/round3_notes_confirmation` and `/datum/unit_test/dq_hc_struct/round3_newscaster_draft_questions`. Existing relevant cases include `/datum/unit_test/dq_fwg3_ask/alien_coil`, `/datum/unit_test/dq_hc_computers/med_print_and_notes`, and `/datum/unit_test/dq_hc_struct/newscaster_draft_is_edited_through_its_window`. These do not yet prove every migrated input. The shared focused batch must also exercise message password/server switching, painter cancellation, claw PIN payment, the food menu, pandemic reason/signature, traffic/magnet settings and the jukebox rights refusal.
