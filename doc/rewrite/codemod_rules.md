# Codemod rules

One section per codemod: the old form, the new form, what must hold for a site to convert, and the residue codes for the sites that stay.
A rule is written from conversions already on master (the commit is named under "Evidence") and from the engine that runs the new form;
a site converts only when its shape matches the rule exactly, and every other site is residue with a code. The codemods live in
`tools/analyze/src/codemods/` (`analyze codemod list`) except the two text codemods in `tools/dx/codemods/`. Each reports its counts
and residue by code; `tools/analyze/codemods/<name>/residue.json` is the committed residue of the analyze ones.

Shared facts. A handler that changes shape changes for all of its callers or for none: every site that names it must convert, nothing else may
call or reference it, and each override of it (a related type that defines the same name) changes the same way. A converted file keeps its
line endings and its comments. `analyze gen` runs after a codemod, and a ratchet baseline row whose line text changed is renamed, never added.

## om_after -> after()

| Old | New |
|---|---|
| `om_after(E, d, proc, args...)` | `after(E, d, proc, with = list(args...))` (no `with` for no args) |
| `after_slot(E, slot, d, proc, args...)` | `after(E, d, proc, key = slot, with = list(args...))` |

Residue: `not_in_ast` (a macro body or inactive `#if`), `reference` (the name used as a value), `value_used` (an `after_slot` result is used: `after()`
returns the id, `after_slot` returned `!!id`). Evidence: the hand conversions of doors and the APC.

## own_set / own_add -> rel_set / rel_add, with the declaration

`rel_set` / `rel_add` dispatch on the var's declared kind (`rel_kind`, code/engine/declare/relations.dm); the old verbs learned an undeclared var as
owned on first use, so a rename alone would turn an owned var into a view. A converted var therefore needs a declaration:

| The var | Added to the `CAPABILITIES` block of the type that declares it |
|---|---|
| already declared (legacy `ownership()`, `OWN` macros, an `owns_*`/`ref_*`/`link` entry on the type or an ancestor) | nothing, the call is renamed |
| a single entity (`own_set`) | `owns_one(nameof(v), /declared/type)` |
| a list (`own_add`) | `owns_many(nameof(v), /element/type)`, with no element type when something `own_set`s a whole list into the var (`own_type_ok()` refuses a list under an element type) |

The block is made after the type's var block when there is none (skipping column-0 comments, `/* */` and preprocessor lines inside the type).

Residue: `extra_args` (`user =`, `into =`, `slot =`, `force =`, `log =`: a transfer, `move_into()` later), `dynamic_var` (the var is not `nameof(x)` or a literal),
`unresolved_receiver` (the holder's type is unknown), `unknown_var`, `untyped_var` (no entity type, a value type, or declared in the vendored TGS API or the defines),
`list_var` (`own_set` on a list var), `scalar_var` (`own_add` on a scalar). Evidence: `rel_*` in the SMES, chargers and vending conversions.

## om_hook / om_unhook -> observe / unobserve

| Old | New |
|---|---|
| `om_hook(source, /datum/om/event/x, listener, PROC_REF(h))` | `observe(source, /datum/notice/x, listener, then(PROC_REF(h)))` (`global.observe` in a type that has an `observe` proc, the mob verb) |
| `om_hook(..., list(e1, e2), ...)` as a statement | one `observe` per event |
| `om_unhook(source, event, listener)` | `unobserve(source, notice, listener)` |
| handler `h(datum/source, datum/om/event/x/event)` | `h(datum/act/notice/A)`; `var/datum/source = A.target` if `source` is used; `var/datum/notice/x/event = A` if `event` is used; `event.f` becomes the notice's field name (`source` -> `source_`, `target` -> `target_`) |

The notice twin of each event is `tools/dx/codemods/om_event_map.json`: only a row whose target is a `/datum/notice/` and that does not read `event.result` converts.
`observe` is a runtime hook, as `om_hook` was, so a hook is never turned into a static `on_notice`. Evidence: the autoclose blocker of `door.dm` (`a31c4eeb38`).

Residue: `argc`, `event_not_literal`, `event_unmapped` (a `before/` guard, `review`, `delete`, `op`, or a result reader), `list_value_used`, `listener_not_src`
(`PROC_REF` names a proc of the listener), `handler_expr`, `handler_blocked` (another caller, a hook of it that does not convert, an unexpected signature,
the event used whole or by a field the notice lacks, a local named `A`), `unhook_unpaired`, `unhook_all`.

## om_hook residue (by hand: the veto form)

`om_hook`, `om_unhook`, `om_unhook_all` and `om_hooked` are deleted. The sites the codemod left (a `before/` guard, a result reader) were converted by hand to the
runtime form of `extend()`: `observe(source, /datum/act/x, listener, parts...)`. The parts are the hook forms of doc section 10 and run on the listener (`A.holder` is the
listener for the hook, `A.target` the observed entity); the hook ends with `unobserve()`, with `unobserve_all(listener)`, or with either end's deletion, through the activation machinery.

| What the old handler did | The form | The caller |
|---|---|---|
| returned a veto flag (`COMPONENT_*` bit 0) | `instead(when(PROC_REF(g)))` for a pure gate, `instead(then(PROC_REF(h)))` when the handler acts; `instead()` for an unconditional takeover | `var/datum/act/x/F = ACT_TRY(E, x, ...)`; `if(!F) return` (refused or taken over); `act_done(F)` when the action goes on, `act_cancel(F)` for a question that only asks |
| returned a veto flag only when it applied | the `then` handler returns `HOOK_DECLINE` when it does not apply; any other value takes the action over and is the reply | the same |
| returned a value with the veto (an `ITEM_INTERACT_*` result, a name, `TRUE` to say handled) | the handler returns the value; the caller reads `ACT_REPLY` after `if(!F)` and `ACT_TAKEN_OVER` says it was taken over rather than refused | `if(!F) return ACT_TAKEN_OVER ? ACT_REPLY : ITEM_INTERACT_BLOCKING` |
| ORed flags into `event.result` or changed a payload list in place (several listeners may) | `adjusts_with(PROC_REF(h))`: `h(datum/act/A)` writes the act's typed fields (`A.protection \|= ...`); it never takes the action over and every one runs, in order | `x = ACT_FINAL(F, field, local)` after the `ACT_TRY` |
| only watched (an after-fact event) | `observe(source, /datum/notice/x, listener, then(PROC_REF(h)))`, the existing form | none |

`om_wants(E, event)` on a hot path becomes `act_wanted(E, /datum/act/x)`. A pure question (`draw_hud`, `body_status`, `geiger_scan`, `relay_movement`, the names) ends `act_cancel(F)` when
nothing took it over: it never publishes a committed notice for an action that did not happen; an action that does go on (`injure`, `attackby`, `attack_hand`, `explode`, `shoot`, `emp`,
`play_cinematic`, `pre_attack`) ends `act_done(F)` once the gates passed, so its notice (`/datum/notice/attacked_by`, `hand_attacked`, `pre_attacked`, ...) is what an observer hears.
A before/ event that behaviours still handle (`attackby`, `attack_hand`) is still emitted after the action's gate; the other 17 are deleted.

Per site (the choice and why; stat and `contributes` are not used because none of these values is a fact that holds while a state lasts: each is read at the moment of the question from
what the listener holds then):

| Site | Event | Form | Why |
|---|---|---|---|
| statue (stasis) | `before/living_injure` | `instead(when())` on `/datum/act/injure` | a pure refusal |
| protean rig (soaks the wearer's injury) | `before/living_injure` | `adjusts_with` on `injure` | it reads kind, zone, flags and amount and acts; it neither refuses nor changes the amount |
| nanoform core dormancy | `before/living_body_status`, `atom_tool_act`, `attackby` | `instead()` on `body_status` (a held-alive question), `instead(then())` on `tool_act` and `attackby` | the first is a veto; the others answer a result (`ITEM_INTERACT_SUCCESS`, `TRUE`) or decline |
| material container, remote materials, material diagnostics | `before/attackby`, `atom_tool_act` | `instead(then())`, `HOOK_DECLINE` when the item is not theirs | the handler does the insert and says whether it did |
| shadekin voice, alt name, visible name | `human_get_voice`, `human_get_alt_name`, `human_get_visible_name` | `instead(then())` on `name_voice`, `name_alt`, `name_visible`; the reply is the name | a veto with a payload: a name replaces the others, it is not composed |
| remote view | `mob_relay_movement`, `mob_handle_hud`, `mob_handle_hud_health_icon` | `instead(then())` on `relay_movement`, `draw_hud`, `draw_health_icon` | the settings object answers whether it handled it |
| radiation effects | `handle_radiation`, `living_irradiate_effect`, `geiger_counter_scan` | `instead(then())` on `live_radiation`, `irradiate`, `geiger_scan` | the handler acts (purges, reports) and answers whether it blocked |
| disposal connection | `disposal_flush`, `disposal_send` | `instead(then())` on `flush_disposal`, `send_disposal` | takes the packet over, declines when no trunk is linked |
| cinematic | `world_play_cinematic` | `instead(then())` on `play_cinematic` of `OM_WORLD` | a playing cinematic blocks the next one, or yields to a global one |
| EMP: robot cell shield, material response | `atom_pre_emp_act` | `adjusts_with` on `emp` | a flag word several listeners OR into; the material's depends on its temperature when the pulse arrives, so a held stat would be stale |
| protean blob hiding | `movable_pre_move` | `instead()` on `pre_move` | an unconditional refusal while hiding |
| artifacts | `atom_ex_act`, `atom_bullet_act` | `instead(then())` on `explode`, `shoot` | triggered artifacts cancel the blast and the shot |
| experiment handler (handheld scanner) | `item_pre_attack` | `instead(then())` on `pre_attack` | cancels the swing when it ran the experiment |
| tests: containment | `before/slot_pre_insert`, `slot_pre_remove` | `instead(when())` on `check_insert`, `check_remove` | the refusal questions of `dq_ledger_refusal()` |

The after-fact events only unit tests watched (`machinery_broken`, `living_injury_explained`, `slot_inserted`, ...) got a notice twin through `TEST_WATCHED` in `tools/dx/gen_om_notices.py`.
The `living_status_stun` veto test was deleted: nothing but a test vetoed it.

## range observers

`connect_range` (the proximity monitor's range connector) is one entry per observer in a grid of 8x8-turf buckets (`code/datums/range_watch.dm`), not a hook per turf: a turf that something
enters, leaves or is created on reads its own bucket (`RANGE_WATCH()`, behind one read of `GLOB.range_watch_count`) and each watcher in it checks the square. Its listener procs take
`(turf, thing, other)` for `RANGE_ENTERED`, `RANGE_EXITED`, `RANGE_INITIALIZED`.

## om_ask -> open_request (generic prompts)

| Old | New |
|---|---|
| `om_ask(M, /datum/om/prompt/confirm, PROC_REF(h), message = m)` | `open_request(src, /datum/prompt/yes_no, PROC_REF(h), answerer = M, question = m, timeout = 0)` |
| `.../text` (`default`, `max_length`, `multiline`, `encode`, `name_text`) | `/datum/prompt/text` (`default`, `max_len`, `multiline`, `encode`, `name_text`) |
| `.../number` (`default`, `min`, `max`) | `/datum/prompt/number` (`default`, `min_value`, `max_value`) |
| `.../choice` (`choices`, `default`, `buttons`) | `/datum/prompt/choice` (same names) |
| `.../color` (`default`) | `/datum/prompt/color` (`default`); the answer `picked_color` becomes `A.answer.answer_value` (a "#rrggbb" text, as before) |
| `title`, `timeout` | `title`, `timeout` (the old default is 0, so it is written whenever absent) |
| `message` | `question` (required: with none the old window showed nothing) |
| `max_length = MAX_NAME_LEN` with no `name_text` | adds `name_text = TRUE` (the old rule: a name-length limit strips name tokens); any other `max_length` without `name_text` is residue |
| handler `h(datum/om/prompt/text/ask)` | `h(datum/act/request/A)` starting with the guard of the old trigger: `if(!A.answer) return`, and for a confirm without `answer_on_no` also `|| !A.answer.answer_value`; `ask.<answer>` -> `A.answer.answer_value`, `ask.answerer` -> `A.request.answerer` |

`/datum/prompt/text` gained `encode` (default TRUE, what its window always did); the old kind's `encode = FALSE` is passed through.
A subtype of a kind with its own state (`/choice/radial`, `/color/<subtype>`, `/text/<subtype>`) is residue: the radial kind has `autopick_single_option`, `require_near`, `click_on_hover`, `user_space` and `uniqueid` and the new choice prompt's radial ring has none of them. `ask_flags` and `requires` re-check the roles when the answer arrives (code/datums/om/ask.dm, `ASK_*`); the request's equivalent is `valid = PROC_REF(x)`, which has no flag helper yet, so those sites wait for one. The same for the 130 sites in a `/datum/om/flow`.

Residue: `argc`, `kind_unsupported` (a subtype of a kind carries its own state and checks), `roles_or_checks` (`asker`, `subject`, `receiver`, `requires`, `ask_flags`,
`optional`, any `cancel_*`, `yes_text`, `no_text`, `ui_refresh`, `key`), `unsupported_param`, `no_message`, `name_text_unknown`, `handler_expr`, `comment_in_call`, `value_used`,
`flow_receiver` (in a `/datum/om/flow`: the flow parks with its question and stops on a cancel), `handler_blocked` (the handler reads more of the prompt than the answer and answerer).

## DECLARE_UI / UI_ACT -> interface() / op(ui_act())

Unit: one host type `T`. All of its legacy UI declarations convert together or none does, because the legacy table and the new interface cannot both describe one type.

| Old (one row each) | New (in `CAPABILITIES(T)`, in the order of the rows) |
|---|---|
| `DECLARE_UI(T, "Window")` | `interface("Window")` |
| `DECLARE_UI(T, "Window", UI_TITLE("Title"))` | `interface("Window", title = "Title")` |
| `UI_ACT(T, "act", proc)` | `op("act", ui_act("act"), then(PROC_REF(proc)))` |
| `UI_ACT(T, "act", proc, UI_ARG_VALUE("a"))` | `op("act", ui_act("act", arg("a")), then(PROC_REF(proc)))` |
| `UI_ARG_NUM("a")` / `UI_ARG_NUM("a", lo, hi)` | `arg("a", num())` / `arg("a", num(lo, hi))` |
| `UI_ARG_INT("a")` / `UI_ARG_INT("a", lo, hi)` | `arg("a", int())` / `arg("a", int(lo, hi))` |
| `UI_DATA(T, "merge:p{schema}")` or `UI_DATA_REPLACE(...)` | the proc `p` becomes `T/ui_data(datum/act/eval/A)`; the row and its schema text are removed |
| `UI_ACT_PROC(T, proc)` header `(mob/user, list/params, datum/tgui/ui, datum/tgui_state/state, action)` | `/T/proc/proc(datum/act/op/A, a, b)`: the declared args as parameters, in the order of the row |

Body of a handler: `params["a"]` for a declared `a` becomes `a`; `user` (if used) is `var/mob/user = A.actor` as the first body line (after the proc's leading settings); a data proc
reads `user` as `var/mob/user = A.actor` the same way. Returns need no change: a handler that returns null, TRUE or FALSE is an OK op (code/engine/parts/run.dm, the report rule),
and the old window refresh is the engine's push after a read changed.

Evidence: the SMES (`afbbe2a3c8`): `DECLARE_UI(.., "Smes")` -> `interface("Smes")`, the four `UI_ACT` rows -> `op("tryinput", ui_act("tryinput"), ...)`, `op("input", ui_act("input", arg("adjust"), arg("target")), ...)`,
`UI_ACT_PROC` -> `(datum/act/op/A, adjust, target)` with `params["target"]` -> `target`, `UI_DATA_REPLACE` + `ui_data_obj_machinery_power_smes(user, ui, state)` -> `ui_data(datum/act/eval/A)`.
Two departures from the SMES, on purpose: `UI_ARG_NUM` keeps its type (`num()`; the SMES wrote a bare `arg()`), and the proc names are kept (the SMES renamed them).
The old `UI_ARG_NUM` / `UI_ARG_INT` also accepted numeric text and rounded; `num()` / `int()` take numbers only (the windows send numbers, the SMES's own `target` comes as text or a number and stays a bare `arg()`).
The window itself is opened through the `tgui_interact(user)` bridge (`ui_open()` finds the interface through `present_interface()`), so callers of `tgui_interact` need no change.

A type converts only when:
- it has exactly one `DECLARE_UI` and no `DECLARE_UI_STATE` (the state's replacement is a requirement on the open op, a decision per state), `UI_WATCH`, `UI_PINNED`, `UI_AUTOUPDATE`, `UI_PREINITIALIZED`, `UI_STATE`, `UI_FROM_VAR` or any other option;
- no other form is used for it: `UI_SUBACT*`, `UI_ACT_NESTED`, `UI_ACT_FORWARD`, `UI_ACT_FALLBACK`, `UI_ACT_OVERRIDE`, `UI_ACT_PREF_PROC`, a second `UI_DATA`;
- no type related to it by path (an ancestor or a descendant) declares any UI row, and it has no `ui_act_allowed`, `tgui_data`, `tgui_act`, `ui_status` or `tgui_interact` override of its own;
- every `UI_ACT` has a literal action name matching `^[a-z0-9_]+$`, a proc with a `UI_ACT_PROC` under it, and argument kinds in {`NUM`, `INT`, `VALUE`} with literal or define bounds;
- every proc is referenced only by its row and its definition, and its body uses none of `ui`, `state`, `action`, `params` other than `params["declared"]`, and `return` or `.` only as null, `TRUE`, `FALSE`, 0 or 1;
- `A` is not a name in the body, and the declared argument names are plain identifiers that are not names used in the body.

`DECLARE_UI_STATE(T, state)` is not a row of the window: it stays where it is and `ui_open()` keeps reading it (`ui_decl_of` finds the marker the row defines whether or not a `DECLARE_UI` stands beside it), so it no longer blocks a type.  A `ui_act_allowed` override is not run by the op path (`present_ui_act` runs a window button as an op before the legacy dispatch), so a type that overrides it is residue (`ui_override`) except for the one shape that is exactly `if(!..()) return FALSE`, `add_fingerprint(ui.user)` (or `user`), `return TRUE` with no related type defining one: that guard is always TRUE, the override is deleted and `add_fingerprint(A.actor)` becomes the first statement of every converted handler (the same effect, once per press, before anything else). Only a type under `/atom` converts: `ui_data` and `present_interface` are on `/atom`, so a `/datum` window (the tgui_* prompt windows, tgui modules, panels) is residue `ui_not_atom` until the new output procs reach `/datum`.

Residue codes: `ui_options`, `ui_state`, `ui_forms` (a form outside the list), `ui_related` (a related type declares UI), `ui_override`, `act_name`, `arg_kind`, `proc_missing`, `proc_shared`, `body_uses` (`ui`, `state`, `action`, other `params`, an odd return), `name_clash`, `data_rows`.

## DECLARE_INTERACTIONS -> op()

Unit: one host type `T` with exactly one `DECLARE_INTERACTIONS(T, specs...)` or one `EXTEND_INTERACTIONS(T, specs...)`. An `EXTEND` converts the same way as a `DECLARE`: ops accumulate down the tree, which is what an extension meant; a type with two declaration rows stays residue.

| Old spec (what the old resolver did: code/datums/interactions/compact.dm) | New entry in `CAPABILITIES(T)` |
|---|---|
| `INTERACT_USE(name, PROC_REF(h))` (self-use of the held item; the return is ignored, base requirement `REQ_SELF_USE_REACH`) | `op("key", in_hand(), label(name), then(PROC_REF(h)))` |
| `INTERACT_HAND(name, PROC_REF(h))` (an empty hand; base requirement `REQ_INTERACTION_REACH`) | `op("key", hand(), label(name), then(PROC_REF(h)))` |
| `INTERACT_INSERT(/held/type, PROC_REF(h), name)` (an item of that type) | `op("key", item(/held/type), label(name), then(PROC_REF(h)))` |
| `INTERACT_ITEM(name, PROC_REF(h))` (any item) | `op("key", item(/obj/item), label(name), then(PROC_REF(h)))` |
| `INTERACT_VERB(name, PROC_REF(h))` (an object verb: the Menu only, no click) | `op("key", menu(), label(name), then(PROC_REF(h)))` |
| `INTERACT_VERB(name, PROC_REF(h), REQ_IN_INVENTORY)` (the old `set src in usr`) | `op("key", menu(), label(name), needs(carried()), then(PROC_REF(h)))` |
| a `null` name | no `label()` (the old name was derived from the proc name) |
| handler `h(mob/a, obj/item/w, datum/interaction/i)` | `h(datum/act/op/A)`; `var/mob/a = A.actor` and `var/<w's type>/w = A.held` as the first body lines (after the leading settings) when used |

The op key is the handler's name without `interaction_` (the whole name when that key is taken by another op anywhere in the tree). The ops are added to the type's
`CAPABILITIES` block, or the block is made where the `DECLARE_INTERACTIONS` stood.

Evidence: the roller and the roller rack (`6234356964`): `INTERACT_USE(null, PROC_REF(interaction_self))` -> `op("unfold", in_hand(), label("Unfold"), then(PROC_REF(unfolded)))` with the handler on `(datum/act/op/A)`,
`var/mob/user = A.actor`, `return OP_OK`; `INTERACT_ITEM` -> `op("loose", item(/obj/item), label("Use"), ...)`; the touch -> `op("touch", hand(), label("Use"), ...)`. Departures on purpose: those conversions chose their own keys and labels and split one handler
into several ops (a `when()` for each branch); the codemod never splits a handler, so a handler that branches stays a candidate only when it can always answer.

Evidence for the verb: the duffelbag tilt (`241131f467`), `INTERACT_VERB("Adjust Duffelbag Angle", ..., REQ_IN_INVENTORY)` -> `op("tilt", menu(), label("Adjust Duffelbag Angle"), needs(carried()), then(...))`. A verb's `held` parameter is not the actor's held item in a menu input, so a verb handler that reads it stays residue (`body_uses`); a verb's return is ignored like a USE.

Why the returns matter: an old HAND, INSERT or ITEM effect that returned falsy let the next candidate (or the type's default) have the input. The op form says the same with `OP_DECLINE` (next section): every
falsy return (`return FALSE`, `return 0`, `return null`, a bare `return`) becomes `return OP_DECLINE`, and a handler converts only when every return is one of those or `TRUE` and the last statement is a return (a handler that falls off its end
answered falsy before and would commit now: residue `handler_returns`). An `INTERACT_USE` ignores its return (always handled), so any handler converts. `INTERACTION_HANDLED_PASS` is the `passes()` part and stays residue.

A type converts only when:
- it is not in a hierarchy with a type that REPLACES what it inherits (a `DECLARE_INTERACTIONS` or a `get_interactions` / `declare_interactions` override that does not call `..()`): ops accumulate down the tree, so a replacement would stop meaning anything. `EXTEND_INTERACTIONS` only adds and never blocks;
- every spec is one of the four kinds above with no requirement argument (`REQ_*`), a literal or `null` name, and `PROC_REF(h)` / `TYPE_PROC_REF(T, h)` as the effect;
- each handler is defined once on `T` with three parameters, no related type defines the same name, and nothing else mentions it (a call, a `PROC_REF`, a `..()`);
- the body does not use the third parameter, `INTERACTION_HANDLED_PASS`, `..()` or a local named `A`.

Residue codes: `interaction_forms` (an `EXTEND_INTERACTIONS`, a `declare_interactions` override or a datum interaction type, a second row, a name or effect that is not a literal), `interaction_related`, `interaction_kind` (`INTERACT_HAND_UNGATED`, `INTERACT_ALT`, `INTERACT_SELF`, `INTERACT_VERB`,
the `_AS`, `_HOSTILE`, `_PEACEFUL`, `_DEFAULT`, `INTERACT_SILICON`, `ROBOT`, `TK`, `OBSERVER` shapes), `requires`, `effect_expr`, `handler_shape`, `handler_shared`, `handler_returns`, `body_uses`, `key_clash`.

## OP_DECLINE: an op handler that is not handled

An op's `then(PROC_REF(h))` handler (or any effect proc) that answers `OP_DECLINE` says "not handled after all": the op ends `ACT_DECLINED` with nothing committed (reservations released, so no cost), nothing told to the actor, no notice
published and no game-log line, and the click goes on to the next candidate whose `when()` holds, then the next, and on to the legacy click handling when none is left. It is the op form of the veto hooks' `HOOK_DECLINE`.

| Old | New |
|---|---|
| an old interaction or attack handler that answered falsy to let the next candidate or the default have the input (`return FALSE`, `return 0`, `return null`, bare `return`) | `return OP_DECLINE` |
| a handler that answered `TRUE` | `return OP_OK` (or `TRUE`; the engine reads both as committed) |

Rules. Decline from the first statement that knows, before anything is written: effects that already ran are not undone (the old code had the same property: its writes before the falsy return stayed). The decline result is
`ACT_DECLINED` (never a filter, not in `ACT_ANY`); `perform_op()` and the test driver return it in `/datum/op_result` when every candidate declined, a player's click returns null (the mob's own click handling runs). An op that is waiting
(`wait()` steps) and declines at its final effect has already spent the wait: decline is for immediate ops. `interact_declare.py` applies the table to `INTERACT_HAND`, `INTERACT_INSERT` and `INTERACT_ITEM` handlers
(tools/dx/codemods/interact_declare.py); the wave that lands it converted 24 types (26 ops). Tests: `dq_gap/op_decline_falls_through`, `dq_gap/op_decline_alone_is_not_handled`.
