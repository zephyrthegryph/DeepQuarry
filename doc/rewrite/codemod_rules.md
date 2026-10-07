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
| `.../color` (`default`) | `/datum/prompt/color` (`default`); the answer `picked_color` becomes `A.answer.value` (a "#rrggbb" text, as before) |
| `title`, `timeout` | `title`, `timeout` (the old default is 0, so it is written whenever absent) |
| `message` | `question` (required: with none the old window showed nothing) |
| `max_length = MAX_NAME_LEN` with no `name_text` | adds `name_text = TRUE` (the old rule: a name-length limit strips name tokens); any other `max_length` without `name_text` is residue |
| handler `h(datum/om/prompt/text/ask)` | `h(datum/act/request/A)` starting with the guard of the old trigger: `if(!A.answer) return`, and for a confirm without `answer_on_no` also `|| !A.answer.value`; `ask.<answer>` -> `A.answer.value`, `ask.answerer` -> `A.request.answerer` |

`/datum/prompt/text` gained `encode` (default TRUE, what its window always did); the old kind's `encode = FALSE` is passed through.
`/datum/om/prompt/choice/radial` (literally) becomes `/datum/prompt/choice` with `radial = TRUE` and the ring's options under the same names (`anchor`, `radius`, `tooltips`, `radial_slice_icon`, `autopick_single_option`, `entry_animation`, `click_on_hover`, `user_space`, `require_near`, `uniqueid`); the answer is `choice`, as for any choice. The old kind differs from the new defaults in two places, so the codemod writes both when they are not given: `anchor = src` (the old ring is anchored on the receiver when that is an atom; outside an atom the site is residue `radial_anchor_unknown`) and `autopick_single_option = TRUE` (a lone choice answers itself; the new kind's default is off so converted callers keep what they had). A radial site needs no `message`.

`ask_flags` and `requires` become request fields re-checked when the answer arrives (`request_recheck()`, code/engine/kernel/requests.dm; a failure ends the request cancelled, so the handler's `if(!A.answer) return` guard drops it, as the old prompt dropped the answer): `ask_flags = ASK_*` is passed through unchanged; `requires = PROMPT_ADMIN(r)` becomes `rights = r`; `requires = PROMPT_USABLE_BY("state")` becomes `usable_state = "state"` (an atom owner only); `list(/datum/om/check/inside_target)` adds `ASK_INSIDE`; `list(/datum/om/check/not_incapacitated)` adds `ASK_CAPABLE`. The asker defaults to the answerer and the subject to the owner when it is an atom, as in the old roles; a site that names `asker`, `subject` or `receiver` stays residue. Any other `requires` is residue `requires_unknown`.

A subtype of a kind with its own state (`/color/<subtype>`, `/text/<subtype>`, `/choice/<subtype>`) is residue: it carries state and checks of its own. The same for the sites in a `/datum/om/flow`.

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
- it has exactly one `DECLARE_UI` and no `UI_WATCH`, `UI_PINNED`, `UI_AUTOUPDATE`, `UI_PREINITIALIZED`, `UI_STATE`, `UI_FROM_VAR` or any other option;
- no other form is used for it: `UI_SUBACT*`, `UI_ACT_NESTED`, `UI_ACT_PREF_PROC`, a second `UI_DATA` (`UI_ACT_FORWARD`, `UI_ACT_FALLBACK` and a descendant's `UI_ACT_OVERRIDE` convert with the window: "Window routing" below);
- no type related to it by path (an ancestor or a descendant) declares any UI row (a descendant that only has `UI_ACT_OVERRIDE` rows of this window's handlers is part of the unit), and it has no `ui_act_allowed`, `tgui_data`, `tgui_act`, `ui_status` or `tgui_interact` override of its own;
- every `UI_ACT` has a literal action name matching `^[a-z0-9_]+$`, a proc with a `UI_ACT_PROC` under it, and argument kinds in {`NUM`, `INT`, `VALUE`} with literal or define bounds;
- every proc is referenced only by its row and its definition, and its body uses none of `ui`, `state`, `action`, `params` other than `params["declared"]`, and `return` or `.` only as null, `TRUE`, `FALSE`, 0 or 1;
- `A` is not a name in the body, and the declared argument names are plain identifiers that are not names used in the body.

`DECLARE_UI_STATE(T, state)` is carried by `interface()`: `DECLARE_UI_STATE(T, GLOB.tgui_physical_state)` becomes `interface("Window", state = nameof(GLOB.tgui_physical_state))` (the name of the state global, read when the window opens, so the declaration never depends on the global init order) and `DECLARE_UI_STATE(T, ADMIN_STATE(R_ADMIN | R_EVENT))` becomes `interface("Window", rights = R_ADMIN | R_EVENT)` (`rights` with no `state` is `ADMIN_STATE(rights)`); the row is deleted. `ui_open()` reads it through `interface_state()` (code/datums/sys/ui.dm), before the host's own `tgui_window_state` var and `ui_rights`, which still apply to a type that sets them (a state that depends on the instance stays a `tgui_state()` override, and a `DECLARE_UI_STATE` of any other expression keeps its row, which `ui_open()` still reads through the legacy marker). Test: `dq_gap/interface_carries_its_state`.  A `ui_act_allowed` override is not run by the op path (`present_ui_act` runs a window button as an op before the legacy dispatch), so a type that overrides it is residue (`ui_override`) except for the one shape that is exactly `if(!..()) return FALSE`, `add_fingerprint(ui.user)` (or `user`), `return TRUE` with no related type defining one: that guard is always TRUE, the override is deleted and `add_fingerprint(A.actor)` becomes the first statement of every converted handler (the same effect, once per press, before anything else). A `ui_act_allowed` that is `if(!..()) return FALSE`, then a pure test of the viewer and host (no `action`, `state`, other `ui`, no effects, no assignments but locals), then `return TRUE`, becomes one silent requirement: `/T/proc/ui_gate(datum/act/op/A)` (the same body, `ui.user` read as `user` from `A.actor`) and `needs(req(PROC_REF(ui_gate), silent = TRUE))` on every op of the type (`silent` is the empty refusal reason, so the viewer is told nothing, as the old bare `return FALSE` did). The `reads` lint judges the body like any requirement: a guard reading an untracked var is residue (`--skip TYPE`, counted as `ui_gate_reads`; run the codemod with `MSYS_NO_PATHCONV=1` on Windows). A `/datum` window converts like an atom (`ui_data` is on `/datum`; a window's buttons have no reach to check); `ui.user` in a handler is `user`; a local named `A` in a handler is renamed `A2` (the act is `A`).

Residue codes: `ui_options`, `ui_state`, `ui_forms` (a form outside the list), `ui_related` (a related type declares UI), `ui_override`, `ui_override_other` (a descendant overrides a proc that is not one of the window's handlers), `ui_forward_expr` (the forwarding proc is not `return <var of the holder>`), `act_name`, `arg_kind`, `proc_missing`, `proc_shared`, `body_uses` (`ui`, `state`, `action`, other `params`, an odd return), `name_clash`, `data_rows`.

## rerun_ask and act_ask -> asks()

A handler that asked its question by re-running itself (`rerun_ask`, and `act_ask` in a window button's handler: the re-run keeps the answers, runs the handler again and the same call then returns the answer) is an op whose question is a workflow step. The step is `asks(/datum/prompt/<kind>, fields = list(...), step = "<key>")` in the op's Wait,
the code after the question is the effect, and the re-run is built in: the op's `when` and `needs` are asked again when the answer arrives, and an answer the kind refuses (`refusal()`: a number the kind will not take, a choice that is not on the list) leaves the question open, so the player is asked again without any handler loop.
Tests: `dq_gap/ask_a_refused_answer_asks_again`, `ask_fields_are_literal_var_or_computed` and the codemod fixtures `interact_declare/asks`, `ui_declare/asks`.

| Old (first statements of the handler) | New |
|---|---|
| `var/x = rerun_ask(user, "k", PROC_REF(self), args, /datum/om/prompt/K, message = m, title = t, ...)` (also `list(user)` as the arguments) then `if(isnull(x))` / `return [value]` | `asks(/datum/prompt/K, fields = list("question" = m, "title" = t, ..., "timeout" = 0), step = "k")` before `then(PROC_REF(self))`; the guard goes; the handler starts `var/x = A.step_value("k")` (when `x` is used) |
| `act_ask(ui.user, action, params, ui, "k", /datum/om/prompt/K, ...)` in a `UI_ACT_PROC` | the same step on the button's op |
| `if(isnull(x) \|\| rest)` | the guard becomes `if(rest)` (the answer is never null now) |
| kinds `text`, `number`, `choice`, `choice/alert` (`buttons = TRUE`), `color`, `confirm` (`yes_text`/`no_text`: "Yes/no labels") | `/datum/prompt/text`, `number`, `choice`, `color`, `yes_no`; the fields are renamed as in the om_ask table (`message` to `question`, `max_length` to `max_len` (with `name_text = TRUE` for `MAX_NAME_LEN`), `min`/`max` to `min_value`/`max_value`) |
| a field that is a literal | written as it is |
| a field that is a var of the holder (`choices = possible_transfer_amounts`) | `nameof(var)`: read from the capture when the question opens |
| a field that is any other expression (`choices = GLOB.x`, `title = "[src]"`) | `computed(PROC_REF(<handler>_<key>_<field>))`, a generated proc `x(datum/act/op/A)` returning the expression (`var/mob/user = A.actor` and the held item are declared when it reads them) |
| a field naming a macro some file `#undef`s (a file-local constant, gone when the generated declaration compiles) | `computed(...)` like any other expression |

A handler's own falsy returns stay as they are in an op with a question (`OP_DECLINE` is for an op that has not waited), and its `PROC_REF(self)` mentions in the questions no longer make the handler `handler_shared`.
The question has to be first: the requirements run before it, whatever stood before it would run after. Residue codes: `ask_not_first` (a statement stands before the first question), `ask_later` (another question after the first effect), `ask_guard` (the question is not followed by `if(isnull(x))` and a return), `ask_kind`
(a prompt kind or subtype this table does not name), `ask_key`, `ask_actor` (the asker is not the actor), `ask_rerun` (the re-run names another proc or other arguments), `ask_fields`, `ask_field_<name>` (a field the new kind has no name for), `name_text_unknown`, `name_clash` (a generated proc's name is taken), `ask_expr`.
Not converted: `verb_ask` and `client_ask` (an admin verb or a client proc is not an op: its code after the question moves into a `request()` callback by hand), `topic_ask`, `flow_ask`/`prompt_flow`, and a handler whose later question depends on an earlier answer (a hand conversion: `asks(..., when = PROC_REF(x))` skips a step by the earlier answer).
The answer is read with `A.step_value("k")` (the prompt's `value`; `A.step_answer("k")` is the prompt itself). A `computed()` field and an `asks(..., when =)`
condition run in the op's context (`A.args`, `A.held`, the earlier steps' answers); `analyze` checks them as such.

**By hand, the shapes the codemod leaves (`ask_not_first`).** A question asked in one case only (after a guard, inside an `if` or a `switch` case on an
argument) is the same `asks()` step with `when = PROC_REF(x)`, `x` the condition the old code tested before asking; the guard itself stays in the
handler, which runs after the answer. A handler that branched on the held item's kind becomes one op per kind (`item(T)`, `tool(Q)`), the question on
the op that asked it. Examples: the bookcase, the paper bin, the gas pumps, the ATM, the shield generator (fw-gaps3, `intended_changes.md`).

## Window routing: UI_ACT_FALLBACK, UI_ACT_FORWARD, UI_ACT_OVERRIDE

The three forms that decided which handler a window action reaches, as op forms (tests `dq_gap/ui_fallback_answers_the_actions_nothing_names`, `ui_forward_and_override_route_the_button`; `ui_declare.py`, fixture `routing`).

| Old | New |
|---|---|
| `UI_ACT_FALLBACK(T, proc)` (every window action no `UI_ACT` row names: an embedded controller's program commands) | `op("key", ui_act("*"), then(PROC_REF(proc)))`: `ui_act("*")` answers every window action no op of the holder names (the named op always wins); the handler is `proc(datum/act/op/A)` and reads which action reached it with `A.window_action()` (`var/action = A.window_action()`). A fallback that must take only some of the actions says so with a requirement, `needs(req(PROC_REF(known), silent = TRUE))`, which also reads `A.window_action()` |
| `UI_ACT_FORWARD(T, proc)` with `proc(mob/user, action)` returning the datum (the sleeper console's window is its sleeper's panel) | `interface("Window", forwards = nameof(var))`: a window action the holder has no op for goes to the datum(s) in `var` (a var of the holder holding one datum or a list); the first target with an op for it answers, as if its own window had sent the button. At most `OP_UI_FORWARD_DEPTH` windows deep. A proc that is not `return <var>` is residue `ui_forward_expr` |
| `UI_ACT_OVERRIDE(U, proc)` (a descendant replaces the handler of a parent's button) | nothing to declare: `then(PROC_REF(proc))` is looked up on the holder, so `/U/proc(datum/act/op/A, args...)` (an override, no `proc/`) is the handler of the parent's op. A descendant that re-declares the button (`UI_ACT` of the same action) re-declares the op: a later declaration of a key replaces the earlier |

A window with a forward and no button is typed from its `ui_shape()` (the typed window needs one: `interface("Window", forwards = ...)` with neither `ui_shape()` nor a `ui_act()` op has nothing to type, an `analyze gen` diagnostic). The tgui `modal_open` / `modal_answer` / `modal_close` actions
have their own rule, "Modals" below.

## Modals: ui_modal_* -> asks(..., inline)

A tgui modal (code/modules/tgui/modal.dm: `ui_modal_opened()` builds it by id, `ui_modal_answered()` uses the answer) is a question shown inside the window. The new form is the question itself: `asks()` with the field `inline = TRUE` shows the prompt as a modal of the asking
holder's window (code/engine/present/prompt_modals.dm) instead of a window of its own, and the op that opens it is bound to the window action `"modal:<id>"` (the engine maps the client's `modal_open` of id `<id>` to it). The client needs no change: it reads `data["modal"]` (added by
`present_tgui_data()`), answers with `modal_answer` and closes with `modal_close`. Test: `dq_gap/modal_is_a_question_in_the_window`.

| Old | New |
|---|---|
| `ui_modal_opened(user, "id", arguments, ...)` case that calls `tgui_modal_input(src, "id", text, delegate, arguments, value, max_length)` | `op("id", ui_act("modal:id", arg("arguments")), asks(/datum/prompt/text, fields = list("question" = text, "default" = value, "max_len" = n, "inline" = TRUE), step = "id"), then(PROC_REF(x)))` |
| `tgui_modal_choice(src, "id", text, delegate, arguments, value, choices)` | `asks(/datum/prompt/choice, fields = list("question" = text, "choices" = ..., "default" = value, "inline" = TRUE))` (a list shown as a dropdown; a radial choice has no inline form) |
| `tgui_modal_boolean(src, "id", text, delegate, delegate_no, arguments, yes_text, no_text)` | `asks(/datum/prompt/yes_no, fields = list("question" = text, "yes_text" = ..., "no_text" = ..., "inline" = TRUE))`; "no" answers FALSE (use `confirms()` semantics with `confirms("text")` when a no should end the op) |
| `tgui_modal_bento(src, "id", text, delegate, arguments, value, choices)`, `tgui_modal_bento_spritesheet` | `asks(/datum/prompt/choice, fields = list("question" = text, "choices" = ..., "default" = value, "bento" = "spritesheet", "inline" = TRUE))` (`"bento" = TRUE` for the image grid): the window answers with an index and the answer is the choice at it |
| `tgui_modal_message(src, "id", text, delegate, arguments)` (a message whose body the client draws from `arguments`) | no question to ask: the `modal:` op's `then()` calls `tgui_modal_message(src, "id", text, null, A.args["arguments"])` (the op replaces the `ui_modal_opened()` case; `modal_close` clears it) |
| `ui_modal_answered(user, "id", answer, arguments, ...)` case | the `then()` handler of the op: `A.answer.value` is the answer (number for a number kind), `A.args["arguments"]` what the client passed |
| chained modals (an answer opens the next one, passing `arguments` on) | one op with several `asks()` steps, each `inline`; the steps replace each other as the window's modal |

One modal per window at a time, as before: opening another ends the first question cancelled, and closing the modal cancels the op (nothing was spent). Kinds with an inline form: text, number, choice (a dropdown or a bento grid; a radial ring has none), yes_no. `"modal_id" = "x"` names the modal of a step when it is not the op's (several steps of one op each their own modal).

## Yes/no labels

`/datum/prompt/yes_no` has `yes_text` and `no_text` ("Yes" / "No"): `asks(/datum/prompt/yes_no, fields = list("question" = ..., "yes_text" = "Confirm", "no_text" = "Cancel"))`, `open_request(src, /datum/prompt/yes_no, PROC_REF(h), yes_text = "Launch", no_text = "Cancel", ...)`, or a kind
with the labels as its defaults (`/datum/prompt/yes_no/x` with `yes_text = "Launch"`). A label that depends on the asker is `computed(PROC_REF(x))`. The labels are the alert window's buttons, the inline modal's `yes_text` / `no_text`, and what `answer_of_button()` calls a yes. The old
`om_ask(..., yes_text = ..., no_text = ...)` is residue `roles_or_checks` of the om_ask codemod (analyze); the labels the hand conversions dropped were restored: the newscaster ("Confirm" / "Cancel"), the records "Delete", the shuttle "Launch", the toilet crystal, the trash pile, the canvas.
Test: `dq_gap/yes_no_carries_its_labels`.

## DECLARE_INTERACTIONS -> op()

Unit: one host type `T` with exactly one `DECLARE_INTERACTIONS(T, specs...)` or one `EXTEND_INTERACTIONS(T, specs...)`. An `EXTEND` converts the same way as a `DECLARE`: ops accumulate down the tree, which is what an extension meant; a type with two declaration rows stays residue.

| Old spec (what the old resolver did: code/datums/interactions/compact.dm) | New entry in `CAPABILITIES(T)` |
|---|---|
| `INTERACT_USE(name, PROC_REF(h))` (self-use of the held item; the return is ignored, base requirement `REQ_SELF_USE_REACH`) | `op("key", in_hand(), label(name), then(PROC_REF(h)))` |
| `INTERACT_HAND(name, PROC_REF(h))` (an empty hand; base requirement `REQ_INTERACTION_REACH`) | `op("key", hand(), label(name), then(PROC_REF(h)))` |
| `INTERACT_INSERT(/held/type, PROC_REF(h), name)` (an item of that type) | `op("key", item(/held/type), label(name), then(PROC_REF(h)))` |
| `INTERACT_ITEM(name, PROC_REF(h))` (any item) | `op("key", item(/obj/item), label(name), then(PROC_REF(h)))` |
| `INTERACT_HAND_UNGATED(name, PROC_REF(h))` (a touch whose old `attack_hand` never called `..()`: no `hand_gate()`) | `op("key", hand(), ungated(), label(name), then(PROC_REF(h)))` |
| `INTERACT_VERB(name, PROC_REF(h))` (an object verb: the Menu only, no click) | `op("key", menu(), label(name), then(PROC_REF(h)))` |
| `INTERACT_VERB(name, PROC_REF(h), REQ_IN_INVENTORY)` (the old `set src in usr`) | `op("key", menu(), label(name), needs(carried()), then(PROC_REF(h)))` |
| `INTERACT_SELF(name, PROC_REF(h))` (use in hand; unlike USE its return counts) | `op("key", in_hand(), label(name), then(PROC_REF(h)))`, falsy returns `OP_DECLINE` |
| `INTERACT_ALT(name, PROC_REF(h))` (alt-click on the holder; the old `click_alt` ran no `hand_gate()`) | `op("key", hand(), ungated(), gesture(GESTURE_ALT), label(name), then(PROC_REF(h)))`, falsy returns `OP_DECLINE` |
| `INTERACT_DRAG(name, PROC_REF(h))` (a mob or item dragged onto the holder; the handler's second parameter is the dragged atom) | `op("key", item(/<the parameter's type, /atom/movable if untyped>), gesture(GESTURE_DRAG), label(name), then(PROC_REF(h)))`, the dragged atom is `A.held`, falsy returns `OP_DECLINE` |
| `INTERACT_TK(name, PROC_REF(h))` (a telekinetic use at range, the old `attack_tk`) | `op("key", tk(), label(name), then(PROC_REF(h)))`, falsy returns `OP_DECLINE` (below) |
| `INTERACT_<kind>_AS(I_X, ...)`, `_HOSTILE` (`I_HURT`), `_PEACEFUL` (`I_HELP`) | the same op with `stance(I_X)` added (`_AS` takes the stance first: `INTERACT_INSERT_AS(I_X, /held, h, name)`) |
| `INTERACT_<kind>_DEFAULT`, `_DEFAULT_AS` (the type's default for the input, tried after everything else it offers) | the same op with `priority(OP_PRIORITY_DEFAULT)` (and `stance()`) |
| a `null` name | no `label()` (the old name was derived from the proc name) |
| handler `h(mob/a, obj/item/w, datum/interaction/i)` | `h(datum/act/op/A)`; `var/mob/a = A.actor` and `var/<w's type>/w = A.held` as the first body lines (after the leading settings) when used |

The op key is the handler's name without `interaction_` (the whole name when that key is taken by another op anywhere in the tree). The ops are added to the type's
`CAPABILITIES` block, or the block is made where the `DECLARE_INTERACTIONS` stood.

Evidence: the roller and the roller rack (`6234356964`): `INTERACT_USE(null, PROC_REF(interaction_self))` -> `op("unfold", in_hand(), label("Unfold"), then(PROC_REF(unfolded)))` with the handler on `(datum/act/op/A)`,
`var/mob/user = A.actor`, `return OP_OK`; `INTERACT_ITEM` -> `op("loose", item(/obj/item), label("Use"), ...)`; the touch -> `op("touch", hand(), label("Use"), ...)`. Departures on purpose: those conversions chose their own keys and labels and split one handler
into several ops (a `when()` for each branch); the codemod never splits a handler, so a handler that branches stays a candidate only when it can always answer.

Evidence for the verb: the duffelbag tilt (`241131f467`), `INTERACT_VERB("Adjust Duffelbag Angle", ..., REQ_IN_INVENTORY)` -> `op("tilt", menu(), label("Adjust Duffelbag Angle"), needs(carried()), then(...))`. A verb's `held` parameter is not the actor's held item in a menu input, so a verb handler that reads it stays residue (`body_uses`); a verb's return is ignored like a USE.

**The hand gate.** The old `attack_hand` passed `hand_gate()` first: a machine's power (`operable(MAINT)`), posture (not lying, not unconscious), dexterity, and the touch signal and unbuckling. A `hand()` binding now applies the equivalent by default, so every converted `INTERACT_HAND` is gated without a part: every hand op is refused for an actor who is unconscious or stunned (`req_not_capable`), and an op on a machine (`/obj/machinery`, through `op_hand_refusal()` = `hand_refusal()`) also for a machine that does not work, an actor who is lying, and an actor who cannot use their hands. `ungated()` opts out of the machine half (the actor half always holds): `INTERACT_HAND_UNGATED` maps to it, and the engine's own construction ladders (`graph_ops.dm`) and bay `take` ops carry it, because building or taking apart a machine is not using it. Test: `dq_p2_engine/a_machines_hand_op_keeps_the_hand_gate`. Found by it: a hand op that must work on a dead or unpowered machine (a panel, a cell, a board) says `ungated()`. The old neural-injury stare and the click sound are effects of `hand_gate()`, not requirements, and are not part of it.

Why the returns matter: an old HAND, INSERT or ITEM effect that returned falsy let the next candidate (or the type's default) have the input. The op form says the same with `OP_DECLINE` (next section): every
falsy return (`return FALSE`, `return 0`, `return null`, a bare `return`) becomes `return OP_DECLINE`, and a handler converts only when every return is one of those or `TRUE` and the last statement is a return (a handler that falls off its end
answered falsy before and would commit now: residue `handler_returns`). An `INTERACT_USE` ignores its return (always handled), so any handler converts. `INTERACTION_HANDLED_PASS` (handled, the input not used up: the old caller let `afterattack` or the loot panel follow) is `return OP_PASS`
(`OP_PASS`, below), in every kind; the constant read any other way (compared, stored) is residue `body_uses`.

**Hierarchies.** `DECLARE_INTERACTIONS` replaces only the specs list (`get_interactions`) of its ancestors, while an `EXTEND_INTERACTIONS` chain (`declare_interactions` calling `..()`) reaches every descendant, DECLARE or not. So an `EXTEND` converts whatever its ancestors declare (155 of the 205 types the old rule held back were an `EXTEND` under a `DECLARE`); it conflicts only with a descendant whose `declare_interactions` override drops the chain (no `..()`), because ops would flow into it. A `DECLARE` conflicts with any related replacer (a `DECLARE` or an override without `..()`): converted, it would inherit the ops of what it replaced. The design's way out is `without(key)` of the parent's ops plus the child's own ops, but it covers 7 types today (a `DECLARE` under or over another), so the codemod leaves them to hand work (`interaction_related`).

A type converts only when:
- it is not in conflict with a replacer, as the paragraph above defines it;
- every spec is one of the four kinds above with no requirement argument (`REQ_*`), a literal or `null` name, and `PROC_REF(h)` / `TYPE_PROC_REF(T, h)` as the effect;
- each handler is defined once on `T` with three parameters, no related type defines the same name, and nothing else mentions it (a call, a `PROC_REF`, a `..()`);
- the body does not use the third parameter, `INTERACTION_HANDLED_PASS` other than as `return INTERACTION_HANDLED_PASS`, `..()` or a local named `A`;
- no two ops of the type take the same input at the same tier for a stance in common (the clash rule of the table build; two `stance()` ops of disjoint stances, or a `_DEFAULT` beside a plain one, do not clash): residue `interaction_overlap`.

Residue codes: `interaction_forms` (an `EXTEND_INTERACTIONS`, a `declare_interactions` override or a datum interaction type, a second row, a name, stance or effect that is not a literal), `interaction_related`, `interaction_kind` (`INTERACT_SILICON`, `ROBOT`, `OBSERVER`
shapes, and any spec the table above does not name), `interaction_overlap`, `requires`, `effect_expr`, `handler_shape`, `handler_shared`, `handler_returns`, `body_uses`, `key_clash`.

**The input forms behind the table** (tests `dq_gap/input_drag_puts_the_dragged_mob_in_held`, `input_alt_is_a_pinned_hand_op`, `input_stance_picks_the_variant`, `input_tk_is_a_provider_for_what_no_hand_reaches`, `op_pass_hands_the_click_on`).
- **drag.** A drag onto the holder resolves as a click with gesture `GESTURE_DRAG` whose held atom is the dragged one, so `item(T)` is the binding (T the dragged thing's type: `/mob/living` for a body scanner) and `gesture(GESTURE_DRAG)` the pin; a drag answers only drag ops, never the hand's.
- **alt-click.** `hand()` pinned to `GESTURE_ALT`. A `hand()` binding applies the hand gate (an unconscious or stunned actor is refused, and on a machine one that does not work, an actor who is lying or cannot use their hands); the old alt-click never ran `hand_gate()`, so the op says `ungated()` (the actor half always holds).
- **stance.** `stance(I_X, ...)` drops the op from a click whose actor's `input_stance()` is not listed (menu picks and `perform_op()` by key ignore it); ops of disjoint stances never clash.
- **telekinesis.** `tk()` is a hand touch that only the telekinesis provider does, and only on a target no hand reaches (next to the actor, or on it, the hand's op answers: the old tk adapter ran for ranged clicks only). The provider is `telekinetic_reach()`,
  declared on `/mob`: `provides(AFF_MANIPULATE | AFF_TELEKINESIS, reach = TK_RANGE, line_of_sight = TRUE)` while `tk_ready()` (a TK mutation, or powered kinesis gloves, and not through a remote view); `add_mutation(TK)`, `remove_mutation(TK)` and a glove's power spent call
  `tk_refresh()`. As the design says, it is a plain `AFF_MANIPULATE` provider, so a telekinetic actor does any `hand()` op on a target it sees within `TK_RANGE` (the old reach was only the types that declared an `INTERACT_TK`); a `tk()` op sits one tier above hand ops so that at range
  the op that means telekinesis goes first. Compartments, requirements and the actor half of the hand gate apply; the machine half never does (a mind has no posture or dexterity).
- **observer.** `INTERACT_OBSERVER(name, PROC_REF(h), reqs...)` (a ghost's click, the old `attack_ghost`) -> `op("key", observer(), label(name), needs(...), then(PROC_REF(h)))`.
  `observer()` needs `AFF_OBSERVE`, which only `/mob/observer/dead` provides; reach is `REACH_ANY`, and the reach gate still checks the provider, so no
  living actor reaches it. A question the old handler opened is the op's `asks()` with `keeps = TARGET_PRESENT` (a ghost is neither adjacent nor alive).
  Test: `dq_gap/input_observe_is_the_ghosts_only`.
- **the actor's mutation.** `req_mutation(M, of = ON_ACTOR)` (a hulk's smash: `when(req_mutation(HULK))`). Test: `dq_gap/req_mutation_reads_the_actor`.
- **pass-through.** `OP_PASS`, below.

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

## OP_PASS: handled, the input not used up

A `then()` handler that answers `OP_PASS` commits the op (its costs, notice and feedback happen) and says the input is not used up: the click goes on to the next candidate whose conditions hold, then the next, and, when the chain ends on a pass, to the
mob's own click handling (a player's click returns null; a driver-built click returns the last result, whose `passed` is TRUE when it ended on a pass). It is the per-return form of the `passes()` part, which passes after every commit. The effects after the one that answered
still run.

| Old | New |
|---|---|
| `return INTERACTION_HANDLED_PASS` in an interaction handler | `return OP_PASS` |
| an op that always passes | `passes()` |

Test: `dq_gap/op_pass_hands_the_click_on`.

## DECLARE_PERIODIC_WHILE and DECLARE_REPEAT -> every()

The target (doc section 3, section 7): the vars the work is gated on are `TRACKED(T, var)`; the work is a type-level `every(interval, then(PROC_REF(x)), when = cond)` in the type's `CAPABILITIES(T)` block. `tools/dx/codemods/periodic_while.py`.

| Old | New |
|---|---|
| `OM_FIELD(T, f, D, CHANGE_EXPLICIT)` (also `OM_FIELD_TYPED`) | `T/var/f = D` and `TRACKED(T, f)` (`TRACKED_BRIDGED(T, f, CHANNEL)` for a channel other than `CHANGE_EXPLICIT`) |
| `DECLARE_PERIODIC_WHILE(T, PERIODIC_SLOW, "f")` | `every(2 SECONDS, then(PROC_REF(<type>_step)), when = nameof(f))`; `PERIODIC_SECOND` is `1 SECOND`, `PERIODIC_FAST` `0.2 SECONDS` (the cadence's own interval) |
| `DECLARE_PERIODIC_WHILE_ALL(T, C, list("a", "!b"))` | `when = cond_all(nameof(a), cond_not(nameof(b)))` |
| a derived field `OM_DERIVE_FIELD(T, d, list(a, b))` whose proc is one `return a \|\| !b && c` | the expression inlined as `cond_any` / `cond_all` / `cond_not` of `nameof()`; the derive line goes (the proc stays for its other callers) |
| `/T/periodic_step(delta)` and every override below T | `/T/proc/<type>_step(datum/act/timer/A)`, overrides `/U/<type>_step(datum/act/timer/A)` (no `proc/` on an override); a body that reads `delta` gets `var/delta = <the interval>` as its first line (written as the constant: the `handlers/context_field` lint does not model an every() context, so `A.dt` is not read) |
| `DECLARE_REPEAT(T, 0.5 SECONDS, proc, "f")` | `every(0.5 SECONDS, then(PROC_REF(proc)), when = nameof(f))`; `proc` keeps its name and takes `(datum/act/timer/A)`; a `null` field has no `when` |
| `DECLARE_REPEAT(T, "delay_proc", proc, ...)` where `delay_proc` is a proc of T | `every(PROC_REF(delay_proc), ...)`; `delay_proc` takes `(datum/act/A)` |

The step name is the last segment of T plus `_step`; one that exists as a proc anywhere is residue `name_clash`.

Semantics kept. The cadence interval is the same, the work runs while the gate holds and not after (a gated run is skipped), and the first step after the gate turns on is one interval later (the old cadence stepped a new member at its next sweep, at most one interval). The every() runs on the holder's own clock, so stasis pauses it. **Parking** (code/engine/actions/every.dm): a type-level every() whose `when =` is only tracked vars of the holder (`nameof(var)`, `cond_not` / `cond_all` / `cond_any` of those) and has no enclosing `when()` block parks while the gate is false (no timer at all) and wakes when the condition publishes true, through a synthesized `on_change` hook, so an idle holder costs nothing, like the old membership. Any other gate (a proc, a stat, a relation hop) polls: the timer runs every interval and a gated run is skipped.

A declaration converts only when:
- T is under `/atom` (`/obj`, `/turf`, `/mob`, `/area`) or a plain `/datum` (armed from `New()`, `lifeform_datum_new`): a `/datum/system` arms its work from `reactions()` (residue `non_atom`);
- the cadence is `PERIODIC_SLOW`, `PERIODIC_SECOND` or `PERIODIC_FAST` (`MACHINE_PIPELINE` is the machine track's: `machine_pipeline`; the continuous lanes: `cadence`);
- no related type has its own PERIODIC_WHILE (the old one replaced its parent's, an every() accumulates: `related_decl`), and for a REPEAT no related type declares the same proc;
- T defines `periodic_step` exactly once, no ancestor defines it (`ancestor_handler`), no body returns `PROCESS_KILL` (an every() cannot end its own work: `handler_kill`), reads a local named `A` (`body_uses`) or takes more than one parameter;
- nothing calls the handler or starts it by hand: no bare mention in a related type, no `x.periodic_step()` on a receiver whose declared type is related to T, no `om_task_periodic` in a related type (`handler_called`, `manual_start`);
- every named field is TRACKED already, or an `OM_FIELD` on T or an ancestor that no other legacy macro line names (`field_shared`), or a derived field as above (`derived_expr`); a plain var, a relation view or a stat is `field_kind` (the var needs a setter and its writers converted first: the appearance codemod's tracked-writes step);
- a REPEAT proc never returns `REPEAT_STOP` (`repeat_stop`: the every() would keep running while the field holds), has no parameters (`handler_params`) and its delay is a literal time or a proc of T (`delay_var`: a var read at each re-arm).

Residue codes: `decl_form`, `machine_pipeline`, `cadence`, `non_atom`, `related_decl`, `handler_shape`, `ancestor_handler`, `handler_called`, `manual_start`, `handler_kill`, `body_uses`, `name_clash`, `field_kind`, `field_shared`, `derived_expr`, `repeat_stop`, `handler_params`, `delay_var`.
Evidence: the hand conversions of the chargers, airlock and light flicker (`7bce9a692a`). Tests: `dq_gap/every_parks_and_wakes`, `every_starts_when_true`, `every_with_a_proc_gate_polls`, `periodic_pinpointer_steps_while_active`, `periodic_jammer_drains_while_on`.

## DECLARE_VERB and GRANT_VERB -> verb_entry() and granted_verb()

The target (doc section 13): a verb a type has is `verb_entry(path, login =, when =, hidden =)` in its `CAPABILITIES(T)` block; a verb granted at run time is `grant(E, granted_verb(path), source)` (the activation ends with `revoke()`, with the source or with the capability that brought it). The engine is code/engine/present/verbs.dm; the verb store (code/datums/om/grant_verbs.dm) stays the only writer of a `verbs` list, and a granted verb shows under the verb's own `set category` tab in the client's stat panel because the store tells the panel on every add and remove. `tools/dx/codemods/verb_decl.py`.

| Old | New |
|---|---|
| `DECLARE_VERB(T, path)` | `verb_entry(path)` in `CAPABILITIES(T)`: on every instance from init |
| `DECLARE_LOGIN_VERB(T, path)` | `verb_entry(path, login = TRUE)`: on a mob once a player has had it |
| `DECLARE_VERB_IF(T, path, "var")` | `verb_entry(path, when = nameof(var))`: while the condition holds; the entry re-evaluates through an `on_change` hook when the var publishes (a `TRACKED` setter or `OM_FIELD`); a `verb_store_refresh()` after a direct write still works |
| `DECLARE_VERB_HIDE(T, path)` | `verb_entry(path, hidden = TRUE)`: never on an instance (it hides what the type inherits) |
| `om_grant(E, GRANT_VERB, path, source)` | `grant(E, granted_verb(path), source)` |
| `om_revoke(E, GRANT_VERB, path, source)` | `revoke(E, granted_verb(path), source)` |
| `VERB_NAMED(path, "Name", "Desc")` as the id | `granted_verb(path, verb_name = "Name", verb_desc = "Desc")` |
| an item's own verb while carried (`held_verb`) | `held_verb(path, slots)` = `while_slotted(slots, granted_verb(path, on = ON_SOURCE))`: the verb is on the item, held by the carrier |
| `grant(E, hidden_verb(path), source)` | unchanged (`hidden_verb()` is the store form; `granted_verb(path, hidden = TRUE)` is the capability one) |

A `verb_entry()` inside a capability is a grant: on while the capability's activation lives and gone with it (`login` and `when` are refused there: use an enclosing `when()` block). `on = ON_SOURCE` puts the verb on the activation's source (an item's verb, listed while a mob carries it).

A declaration converts when T is under `/atom` (`non_atom`), its verb is a path literal (`verb_expr`) and the macro is one line (`decl_form`). A grant statement converts only when it is a statement of its own (its value unused), its source is a datum expression (a text source is `grant_shared`: the old `om_grant` took one), and every site that names the same path converts too: a path another site grants or revokes through `om_grant_each`, `om_revoke_each`, `om_revoke_all_of`, `om_grant_for` or a text source is `grant_shared`, and any such site is `grant_form`. Reason: a verb granted by `grant()` leaves a live activation, so a revoke of the same verb through the old store call would leave it behind and the next `grant()` from that source would find it and do nothing.

Residue codes: `decl_form`, `non_atom`, `verb_expr`, `grant_shared`, `grant_form`. A gameplay ability that a verb starts is an op under "Abilities" (`menu()`), a conversion by hand; a verb entry is for what the client does (doc section 13: the layering lint will reject it under `code/content`). Tests: `dq_gap/verb_entries_follow_their_conditions`, `granted_verb_follows_its_source`, `verb_entry_in_a_capability_is_a_grant`, `dq_eg2/held_verb_follows_the_carrier`.

## DECLARE_APPEARANCE_PROC -> draw(look)

The target (doc section 13): a type's look is `draw(datum/look/look)`, the one output that says how it appears; the vars it reads are `TRACKED(T, var)` and every writer of such a var uses the setter, so the generated reads (`analyze gen reads`, `code/_generated/reads.dm` through `analyze gen derived_reads`) redraw it when one changes and no `update_icon()` follows the write. `tools/dx/codemods/appearance_draw.py`.

| Old (`DECLARE_APPEARANCE_PROC(T, TYPE_PROC_REF(/atom, appearance_overlays), list())` and `/T/appearance_overlays()`) | New (`/T/draw(datum/look/look)`) |
|---|---|
| `. = list()` | removed (the look is the accumulator) |
| `. = ..()`, `. += ..()`, `..()` as the first statement | `..()` first (a draw without one gets it: the capabilities' and look layers' draws run in it) |
| `. += "state"` / `. += image(...)` / `. += GLOB.x.y(...)` / `. += list(a, b)` / `. += local_image` | `look.overlay(x)` for each (a local declared `var/image/I` counts; a bare identifier of any other kind is residue) |
| `icon_state = x` | `look.state(x)` |
| `color = x`, `alpha`, `layer`, `plane`, `dir`, `icon`, `transform` | `look.color = x` and so on |
| `return` / `return .` | `return` |
| a var the body reads that is not tracked | `TRACKED(U, var)` after its type block (`SETTER(U, var)` when the type has its own `set_<var>()`), and an `OM_FIELD(U, var, D, CHANGE_EXPLICIT)` becomes `U/var/var = D` plus `TRACKED(U, var)` (`TRACKED_BRIDGED` for another channel): the lints count only TRACKED, SETTER and relations |
| a write `var = x`, `var += x`, `var \|= x`, `var++`, `O.var = x` | `set_var(x)`, `set_var(var + (x))`, `set_var(var \| (x))`, `set_var(var + 1)`, `O.set_var(x)` (statement-level writes only) |

Residue codes, with the reason in the report. The proc stays as it is when: `reads_icon_state` (it reads `icon_state` other than `initial(icon_state)`: the new draw cannot see the previous state), `side_effect` (a call that is not a look call: a sound, a light, a flick: it moves to the handler that changes the state), `writes_state` (it writes `name`, `desc`, `pixel_x` or any var of the holder), `dot_use` (`.` used as a value), `returns_value`, `super_late` (`..()` not first), `overlay_expr` (`. += x` of an expression whose kind is unknown), `appearance_other` (the type or an ancestor also has `APPEARANCE_TEMPLATE`, `APPEARANCE_LEVEL`, `APPEARANCE_EMISSIVE`, `APPEARANCE_SLOT`, `APPEARANCE_NONE` or `DECLARE_APPEARANCE`), `related_def` (a related type defines `appearance_overlays` too: a chain converts whole or not at all), `derived_declared` (a type in the chain has a `derived()`: it declares the draw's reads with `drawn_from`, by hand), `hop_read` (it reads through a var, `paddles.combat`: the far var must be tracked by hand), `handler_shape`, `non_atom`, and `var:<code>:<name>` when a var it reads cannot be tracked: `shared_name` (its name is declared on unrelated types, so a write `O.name = x` cannot be assigned to this one), `write_form` (a write inside a larger statement or a macro), `builtin_var`, `decl_shape`, `field_shared` (another legacy macro names the OM_FIELD).
Evidence: the cell charger (`7bce9a692a`), which also dropped its `add_overlay()` call in Initialize. The tracked var's setter publishes the change; the draw is the output the refresh engine re-runs. Tests: `dq_gap/converted_draw_follows_its_tracked_var`.

## The draw sweep: every legacy appearance form -> draw(look)

`python tools/dx/codemods/look_sweep.py <mode> [--apply] [--sites] ...` (modes below; modules `look_convert.py`, `look_track.py`). It extends the
`DECLARE_APPEARANCE_PROC -> draw(look)` rule above to every legacy form and to the `update_icon()` calls around them.

| Mode | What it does |
|---|---|
| `convert [--types T...] [--report R] [--show]` | A **component** (a set of drawing types joined by ancestry) converts whole or not at all. Per type, in the legacy order: `..()`, the template as `look.state("...")` (`{x}` is `[x]`, `[x()]` for a reader proc, `{x?A:B}` is `[x ? "A" : "B"]`), each `DECLARE_APPEARANCE` layer as `if(x == 1)` or `switch("[x]")` of `look.state()` / `look.overlay()` / `look.set_icon()` / `look.set_color()`, `APPEARANCE_NONE` as `look.state(null)` plus `look.hide()` of what the ancestors draw, then the provider body (`. += x` is `look.overlay(x)`, `icon_state = x` is `look.state(x)`, `item_state` is `look.held_state()`, `name`/`desc` are `look.identity()`, `set_light()` is `look.light()` / `look.light_off()`, `flick(x, src)` is `look.play_flick(x)`). A provider that reads its own `icon_state` keeps it in `var/drawn_state = look.state_so_far(src)`. A chain whose subtype provider replaced its parent's (no `..()`) keeps that dispatch: the top type's draw calls `look_parts(look)`, which each type overrides. |
| `calls --report R` | The `update_icon()` calls on a converted component's types: gone where the draw reads only tracked state, in `Initialize()` (the first refresh draws every atom after its init) and in a dispatched handler (a proc taking a `datum/act`); `changed(src)` (`changed(X)`) where it reads state nothing publishes. `--all`: the same for every call whose receiver's chain has no legacy declaration, judged by the chain's `draw()` procs. |
| `generic [--paths P...]` | `X.update_icon()` (and `if(c) X.update_icon()`) on an /atom, /atom/movable, /obj, /mob, /mob/living, /turf, /obj/item, /obj/structure, /obj/machinery or /obj/effect receiver becomes `redraw(X)`: one redraw request for drawn and legacy types (a drawn type is redrawn by the look refresh it marks; a legacy type runs its `update_icon()` on the spot, as the call did). Skips the folders other sessions own (`code/game/machinery`, `code/modules/power`) and the redraw machinery. |
| `dead` | Deletes the `update_icon()` calls whose receiver's chain has no legacy declaration and no `update_icon()` override (the base proc only re-applies a declaration, so they did nothing). |
| `track` | Each var a `draw()` reads that nothing publishes becomes `TRACKED(U, var)` on its one declaring type, every write in the tree the setter (`v = x` -> `set_v(x)`, `v += x` -> `set_v(v + (x))`, `X.v = x` -> `X.set_v(x)`, also as a one-line `if(c)` tail). Left as they are: shared names, writes inside expressions or macros, a hand-written `set_<var>()` in the chain, writes in folders another session owns (`--owned-ok` takes them). |
| `prune [--base ref]` | The `changed()` requests added since `ref` whose receiver's draws now read only tracked state go. |
| `audit` | The `draw()` chains that still read state nothing publishes, with what they read. |

**What does not convert** (the component stays legacy; `--sites` lists them by code): a draw that would read through another object
(`hop_read`: `beaker.reagents.total_volume`, `ammo_magazine.stored_ammo`) or write any object's member (`member_write`: building an image by
`I.color = ...`; use `look_appearance(icon, state, color =, ...)`), a provider that calls something with effects (`side_effect:<proc>`), writes
other state (`writes_state:<var>`), reads `overlays`/`underlays` (`reads_layers`), calls `..()` late (`super_late`), an `update_icon()` override,
`APPEARANCE_LEVEL` / `_EMISSIVE` / `_SLOT` (by hand). A `draw()` and its `look_parts()` read only tracked state and write nothing
(`sys/dx_reactive`); they change no atom either (`sys/dx_review` `output_side_effect`).

**The residue that now converts** (`convert`; `look_convert.py` documents each):

| Shape in the provider | Becomes |
|---|---|
| `add_eyes()` / `update_charge(x)`: a call of a proc of the type | `look.effect(PROC_REF(add_eyes))` / `look.effect(PROC_REF(update_charge), x)`: runs when the look is applied, outside the draw |
| `soundloop.start()` on a var of the holder | `look.effect(PROC_REF(look_effect_soundloop_start))` and a one-line helper proc `look_effect_soundloop_start()` after the draw |
| `x = v` on a var of the holder that the draw never reads | `look.effect(PROC_REF(look_effect_set_x), v)` and a generated setter; a cache the draw reads, `x += v` and a write through a local stay residue |
| `root.var` where root is a var of the holder | `look.watch(root)`: the holder redraws when the other end publishes a change |
| `var/image/I = image(...)`, `I.pixel_y = ...` (plane, layer, alpha, color, dir, appearance_flags), `. += I` | `look.overlay(look_overlay_image(icon, state, pixel_y = ...))` |
| one `..()` in the middle of the body | stays where it is in the draw |
| `H.update_inv_l_hand()` on the holder | a comment: the look redraws the worn slot when it changes the sprite |

Still hand work: `reads_layers`, an `update_icon()` or `changed()` call inside the provider, a late `..()` under a condition or in a type that has its
own `draw()`, an image rebuilt in a branch, a cached image (`GLOB.x_cache`), `multi_def`, `look_var_read`, `layer_override`, `APPEARANCE_LEVEL`.

**The look's additions** (`code/datums/capabilities/look.dm`): `look.state()` returns the state; `look.state_so_far(A)`; `look.light_off()` (an
explicit `set_light(0)`); `look.held_state(state)` and `look.identity(name =, desc =)` (left as they are when a draw does not set them);
`look_appearance()`; when a look changes an atom's sprite its generic emissive blocker follows (`look_resync_emissive_blocker()`) and the
slot that holds or wears an item redraws (`look_redraw_worn()`).

**Pins.** Before a batch, `bash tools/dq_pin.sh --look-tree /root/type ...` records every subtype's look under the converted roots; after it,
`bash tools/dq_focused_test.sh dq_look_tree_pin` lists each row that changed (snapshot_pins.md, "Look pins").

**Ratchet.** `look_converted` (`tools/analyze/src/lints/look_converted.rs`): a hard ban on `update_icon()` and the legacy declarations under the
folders of `[lint.look_converted.lists] folders`; a folder joins once the sweep cleared it.

## reagents: DECLARE_REAGENTS family -> reagents() entries

`python tools/dx/codemods/reagents_decl.py [--check]` (a text codemod; design: `reagents.md`).

| Old | New, in the type's `CAPABILITIES` block |
|---|---|
| a declaration on a type with no declaring ancestor | `reagents(V, starts = C, tint =, holder =, starts_from =)` with the type's whole effective declaration |
| a declaration on a subtype | `configure(reagents(volume = V, add = C, tint = TRUE, holder = H))` with only what its own lines give; nothing when they give nothing |
| `DECLARE_NO_REAGENTS(T)` under a declaring ancestor | `without(CAP_REAGENTS)` |
| `DECLARE_NO_REAGENTS(T)` then a declaration on the same type | `configure(reagents(starts = C))` (and `volume =` when it changed) |
| a string volume or var name | `nameof(v)` |

The chain is read over the whole tree first (an ancestor is a path prefix; no declaring type sets `parent_type`). The entry goes under the
type's existing header in any file, else the first declaration line becomes the block in place; a trailing comment stays on the entry.
Residue: `parse`, `trailing_code`, `indented_next` (the new block would swallow an indented line after it), `parent_traits` (drop then
re-declare under a tinted or typed parent), `from_var_subtype`. The run on master had none. Evidence: `dq_reagents_start_snapshot`
recorded every declaring root's subtree on the legacy code and matched after. A file-local `#define` used as a volume cannot be read by
the generated table (`COOLANT_MAX` in the radiocarbon spectrometer): write the number.
