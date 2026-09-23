# Refactor brief (agents)

This brief implements two design documents; read both first:
- `doc/health_system_review.md`
- `doc/mob_life_architecture.md` (its §8 roadmap is authoritative)

Also read AGENTS.md and `doc/body_architecture.md`.

## Decisions already made by the user
- **Modifiers:** convert modifier numeric fields to body factors. Medical fields first, then combat fields; both fully converted, with no adapter.
- **Readouts:** replace the four-number brute/burn/tox/oxy readouts everywhere with vitals plus findings.
- **Asphyxia:** DELETE `INJURY_ASPHYXIA` and `INJURY_CATEGORY_ASPHYXIA`. Express every source as a mechanism: a factor restriction, breath quality, or a chemical factor. Where there is truly no mechanism, use `add_oxygen_debt()`.
- **Hibernation:** mob hibernation for ALL mobs, players included, once their systems are event-driven.
- **Proteans and prometheans:** one mob with forms, as a component. No second simple_mob.
- **No shims.** Delete what you replace. Don't comment code out. Git is the history.

## Rules
- Edit ONLY the files in your slice. If something outside your slice must change, list it in your report with the exact change.
- Don't touch `code/ATMOSPHERICS/**`; another session owns it.
- Do NOT run dm.exe or tests. The lead compiles centrally between waves, so write carefully and grep to verify.
- New files: create them, and list them in your report for the .dme. Do NOT edit `deepquarry.dme`, except the lead.
- Follow the AGENTS.md DM standards:
  - absolute paths
  - no `:` operator
  - SIGNAL_HANDLER in signal handlers
  - PROC_REF macros for callbacks
  - time defines instead of raw numbers
  - lazy lists
  - `Destroy()` cleanup
- Preserve CRLF line endings in files that have them. Edit with the Edit tool, or with Python using `newline=''`.
- Keep existing debug and trace logging, and add logging for new subsystems and hibernation.
- Keep existing unit tests passing, updating them when an API legitimately changes. Add tests for the new behaviour.
- Don't spawn sub-agents. Do the work yourself.

## Report format
1. Files changed and new files.
2. What was built.
3. Cross-slice changes needed, with exact edits.
4. Anything not done, and why.
