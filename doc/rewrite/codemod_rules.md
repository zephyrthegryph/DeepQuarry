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

## om_ask -> open_request (generic prompts)

| Old | New |
|---|---|
| `om_ask(M, /datum/om/prompt/confirm, PROC_REF(h), message = m)` | `open_request(src, /datum/prompt/yes_no, PROC_REF(h), answerer = M, question = m, timeout = 0)` |
| `.../text` (`default`, `max_length`, `multiline`, `encode`, `name_text`) | `/datum/prompt/text` (`default`, `max_len`, `multiline`, `encode`, `name_text`) |
| `.../number` (`default`, `min`, `max`) | `/datum/prompt/number` (`default`, `min_value`, `max_value`) |
| `.../choice` (`choices`, `default`, `buttons`) | `/datum/prompt/choice` (same names) |
| `title`, `timeout` | `title`, `timeout` (the old default is 0, so it is written whenever absent) |
| `message` | `question` (required: with none the old window showed nothing) |
| `max_length = MAX_NAME_LEN` with no `name_text` | adds `name_text = TRUE` (the old rule: a name-length limit strips name tokens); any other `max_length` without `name_text` is residue |
| handler `h(datum/om/prompt/text/ask)` | `h(datum/act/request/A)` starting with the guard of the old trigger: `if(!A.answer) return`, and for a confirm without `answer_on_no` also `|| !A.answer.answer_value`; `ask.<answer>` -> `A.answer.answer_value`, `ask.answerer` -> `A.request.answerer` |

`/datum/prompt/text` gained `encode` (default TRUE, what its window always did); the old kind's `encode = FALSE` is passed through.
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

Residue codes: `ui_options`, `ui_state`, `ui_forms` (a form outside the list), `ui_related` (a related type declares UI), `ui_override`, `act_name`, `arg_kind`, `proc_missing`, `proc_shared`, `body_uses` (`ui`, `state`, `action`, other `params`, an odd return), `name_clash`, `data_rows`.

## DECLARE_INTERACTIONS -> op()

(Written with its codemod.)
