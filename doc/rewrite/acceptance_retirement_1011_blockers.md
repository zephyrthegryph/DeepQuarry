# Acceptance retirement preparation: remaining handoff dependencies

This branch contains unverified source preparation. It is not a finished or
stamped landing, and its requirement/compiler bans have not been verified.

The preceding 149-table batch, `codex/acceptance-final-1011`, passed the normal
gate on `8a27794954eaeeffe6580b74ce8b5adff14bca4f`: production compilation,
DreamChecker, ratchets, and 41 focused tests passed. The outer lane-ready wrapper
then refused the runtime evidence because its commit is `8a27794954`, while the
wrapper requires the full SHA. No lane-ready stamp was reconstructed.

The last 24 tables require genuine garment name/gender publication so cached
refusal wording remains correct. Runtime writers and registered engine identity
writers have setter-based preparation here. Four constructor writes remain for
the init lane, as explicitly directed by the user:

- `code/modules/clothing/accessories/hands.dm`: material bracelet Initialize,
  `name = "[material.display_name] bracelet"`.
- `code/modules/clothing/accessories/rings.dm`: material ring Initialize,
  `name = "[material.display_name] ring"`.
- `code/modules/clothing/gloves/miscellaneous.dm`: ranger gloves Initialize,
  `name = "[glovecolor] ranger gloves"`.
- `code/modules/clothing/shoes/miscellaneous.dm`: ranger boots Initialize,
  `name = "[bootcolor] ranger boots"`.

Those assignments must use their real name setter once the garment tracking
declarations land. They have not been changed here, exempted, annotated, or
added to a baseline. Until that dependency closes, this preparation cannot be
landed with clean tracked-write ratchets.

Native request outcome constants such as `REQ_CANCELLED` remain request
protocol values. They are not renamed to obtain a lexical `REQ_` count of zero.
The retirement targets are the legacy requirement macros and predicate compiler.
