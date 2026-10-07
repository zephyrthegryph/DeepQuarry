# Request workflow migration: petrification and VR

Source inspection only; no build, generation, lint or runtime test performed.

## Implemented on existing native workflow

Petrification's existing `set_option` UI op now asks its operator for tint or
text through two conditional `asks()` steps before its effect. It retains the
same UI action and option argument; it does not dispatch a second operation.
Prompt preparation preserves titles, current defaults, unlimited timeout,
usable-state checks and color normalization. The effect reads `step_value`
or `step_answer`, retains text sanitization and adjective suffix handling,
and updates the window. Cancelling either native step performs no setting write.
Boolean options and target selection retain their existing paths.

Two former `open_request()` sites were removed. Sixteen remain across the five
owned files. They were preserved because the existing engine cannot represent
their complete workflows faithfully merely by relocating the prompt call.

## Shared engine constraints

`code/engine/parts/run.dm`, `op_request_fields()` (near line 704), overwrites
the prompt's `answerer` with `A.actor`, after reading even computed fields.
Consequently, `asks(fields = list("answerer" = computed(...)))` cannot ask
a selected third party or the new body receiving a transferred mind.

The workflow ordering contract puts effects after the asks/waits phase. VR
requires real body creation, relation changes, mind/client transfer and then
prompting the resulting avatar. Reordering those effects after the name prompt
changes which body/client is asked and its visible state. Starting another op
from an effect does not migrate this workflow under the requested contract.

Notice/timer callbacks do not have a pending native op act. Transport entry and
VR's delayed/automatic entry therefore additionally require a genuine workflow
entry contract; attaching `asks()` to a notice's ordinary `then()` handler or
renaming `open_request()` is not such a contract.

`verb_entry()` (`code/engine/present/verbs.dm:25`) records an `ENTRY_VERB`
with a raw proc path. The verb store adds that path to the actual verbs list
(`verb_store.dm:249`). It does not by itself bind the click to a native op or
provide a pending act that can own `asks()`.

## Preserved sites and their specific constraints

Line numbers below describe the inspected source; subsequent edits may shift them.

| File / site | Constraint |
|---|---|
| `petrification.dm`, target selection (`set_input`) | Begins a linked three-party workflow: operator chooses target; that target confirms twice. The first question alone could fit asks, but converting it while leaving a callback-started request chain would split rather than migrate the complete operation. |
| `petrification.dm`, `petrify_target_chosen` | First consent must ask selected human H, not operator A.actor; preserve captured operator, validity/range and cancellation messaging. |
| `petrification.dm`, `first_confirmed` | Second consent again asks H and must preserve last-warning ordering, operator validity and final target validation. |
| `transportpod.dm:39`, `ask_to_launch` | Notice-started workflow asks N.occupant, including bump/drag/slot entry. Cancellation ejects; confirmation sets transit and warmup. No pending op / selectable answerer contract exists on that notice. |
| `ar_console.dm:124`, engage confirmation | Entry helper is reached through occupancy/delayed entry, asks occupant and can exit on explicit no. Native migration must preserve inherited alien entry/exit dispatch and response behavior before body handoff. |
| `ar_console.dm:172`, new-avatar name | Avatar construction, equipment, preferences and mind transfer occur before naming; prompt must address avatar and then original flow ejects it into the turf. Requires effect-before-prompt sequencing and participant handoff. |
| `ar_console.dm:180`, existing-avatar name | Existing avatar is named around a mind transfer; correct recipient is avatar, with `asked_is_avatar` validity. Cannot substitute occupant actor. |
| `vr_console.dm:233`, leave VR | Other user's eject request asks the avatar for consent; generic handler selects normal/alien exit. Answerer differs from initiator, and cancellation must retain occupant/body. |
| `vr_console.dm:284`, reuse avatar | Entry resolves/sets avatar relation before asking occupant; explicit no clears both VR relations before later choices, whereas cancellation leaves them. The whole workflow needs truthful branching/mutation order and delayed-entry context. |
| `vr_console.dm:305`, location | Occupant must remain in pod; location answer belongs to the same entry workflow and is carried into creature choice, then body creation and naming. The choices could fit a pre-effect asks sequence, but that alone does not migrate the subsequent handoff/name stage. |
| `vr_console.dm:322`, as creature | Uses prior location and original occupant; conditional creature step must preserve the explicit-no human path versus cancellation. Shares full-entry context/handoff gap. |
| `vr_console.dm:329`, creature choice | Choice uses original occupant and preserved location; afterwards body may transform again. Shares full-entry context/handoff gap. |
| `vr_console.dm:388`, avatar name | Opens after avatar creation, mind transfer, equip, DNA initialization and optional transformation. Requires actual resulting avatar identity and client, not former occupant actor. |
| `vr_procs.dm:37`, transform creature verb | Granted raw verb has no existing native op binding; simply converting its registration to `verb_entry()` still invokes the raw proc. Preserve consciousness gate and post-transform grant/state. |
| `vr_procs.dm:60`, ghost-avatar logout verb | Same raw-verb entry gap; confirmation must precede releasing vore contents, dropping inventory, ghostization and disposal. |
| `vr_procs.dm:105`, ghost-avatar name | Programmatic helper follows new body spawn, key assignment, preferences, equipment, grants and admin logging in `fake_enter_vr`; no existing pending op spans those effects and prompt. |

These are implementation gaps in workflow entry/participant/stage contracts,
not claims that the standalone request API is broken. No alias, request wrapper,
new op dispatch, participant mutation or engine workaround was added to hide them.
