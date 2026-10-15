# Physical silicon consumer migration, 2026-10-15

Source-only supplemental cohort in `codex/silicon-remote`. Root owns manifests,
baseline updates, commits and verification. No jobs were run for this cohort.

## Ten former silicon-entry cases

* Flash: remove unreachable robot animation after the existing carbon-only guard.
* Robot suit: native assembly requirement asks the actor's hardware credential;
  only an AI shell rejects an AI-remote MMI, with the original refusal text.
* Girder: actual actor supplies wall-plating duration, 4 seconds or borg 1.5 seconds.
* Buckling: actual actor performs physical admission and the original seat transaction;
  pAI supplies no transaction. No remote authority substitutes for adjacency/body state.
* Mine: exposed wiring opens through the actor transaction, which AI cannot perform.
* Item unequip: actor inventory model honors canremove and slot access; silicon's
  slotless gripper admission remains available to all silicon subtypes.
* Cuffs/tape: actual aggressive grab or actor hardware/self evidence authorizes work.
  Cuffs require adjacent borg hardware, tape retains its distinct non-adjacent rule.
  Existing start and completion consumers both use that common evidence.
* Storage: human/borg actor transactions perform the original incapacity, adjacency,
  belly and actual item-drop sequence. AI and other bodies have no dump transaction.
* Railing/structure: final native rotation ops and ordered physical requirements replace
  the only two consumers of can_touch; the unused generic helper is removed.

All new provider methods live in `code/modules/mob/silicon_physical_providers.dm`.
No dispatch implementation branches on silicon actor kind. Actor-kind requirements are
explicit native parts where appropriate; data/credential/physical transactions use actual
polymorphic actors, not a renamed boolean type-test wrapper.

## Exact pin presentation cause

The green old physical capture records railing, handcuffs and backpack. Railing's old
three granted rotation verbs become three declared native menu ops (same direction
changes and original messages). Native requirements also expose the existing fastened
Flip Railing refusal in its menu instead of waiting for the effect to report it.
This presentation class is intentional; it does not authorize unrelated pin changes.
AI still cannot move/rotate the railing; borg physical reach and anchoring still apply.
The cuffs and storage actor outcomes must otherwise match the old capture.

## New focused coverage

* dq_silicon/physical_inventory_and_work
* dq_silicon/physical_flash_guard
* dq_silicon/physical_shell_credential
* dq_silicon/physical_restraint_evidence
* dq_silicon/physical_storage_dump
* dq_silicon/physical_railing_ops

Fixtures use actual actors, native storage insertion and drop, actual grab construction,
and native railing menu dispatch. Their results remain unverified pending root's one
coordinated batch; no passing result or stamp is claimed here.
