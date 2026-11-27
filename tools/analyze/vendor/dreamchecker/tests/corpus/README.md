# DreamChecker corpus

The oracle for porting DreamChecker onto the compiler front end's tree (`doc/rewrite/proposals/lean_unified.md`, "2b DREAMCHECKER").

- `cases/*.dm`: one project file each. `<suite>__<test>.dm` are the vendored crate's own test snippets (`tests/*.rs` before the
  port); `seed__*.dm` make every other DreamChecker diagnostic kind fire (control flow, settings and directives, static types and
  fields, sleep and purity call trees, filters, keyword arguments, BYOND constants).
- `expected/<case>.txt`: every diagnostic DreamChecker registered on dreammaker's parse (every severity, line and column, error type,
  notes), as `dq_analyze::dreamchecker::render` prints it. Recorded with the checker on dreammaker's parse, which is now removed: these
  files are the record of what it said.
- `expected/<case>.dmbc.txt`: the native checker's output where it differs on purpose (`DQ_DC_CORPUS_BLESS_NATIVE=1`). Every such
  file is listed below with its reason. None of them is a DreamChecker check reading the tree differently: each is a parse.

`tools/analyze/tests/dreamchecker_corpus.rs` runs the checker on every case, serial and on three threads.

## Intended differences

The compiler front end follows BYOND's grammar and refuses what BYOND refuses; dreammaker's parser has its own grammar and its own
syntax errors. A body dreammaker cannot parse has no code there (no check runs on it, only the parse error is reported); the front end
parses it, so the checks run and the parse error does not exist. A tree BYOND refuses is refused whole.

| Case | dreammaker | Compiler front end |
|---|---|---|
| `branch_eval__for_kv_key_check`, `_value_check`, `_var_check` | parse error in `for (var/k = 5, v in A)`, `for (var/k, 0 in A)`, `for (k, v in A)` | parsed as a key-value loop; an undeclared key is `undefined var` |
| `call_ext__call_ext_missing_call` | parse error: `call_ext(1, 2)` without its call | a call of an undefined global proc |
| `directive__final_proc`, `directive__final_proc_intermix` | `proc/final/test()` is a final proc | BYOND refuses the tree ("invalid procedure name") |
| `new__new_dot`, `new__new_precedence` | parse errors at `new foo()()`, `new L[1]()` | BYOND accepts them; the body is checked |
| `operator__ambig_in_ternary_cond` | parse error in `i ? 1 in list() : 2` | parsed; `i` is undefined there |
| `operator__in_ambig`, `seed__calls` | `x = 1 in L` and `x ? 1 : 2 in L` read as `(..) in L`: "ambiguous `=`/ternary on left side of an `in`" | BYOND's precedence: `x = (1 in L)`, `x ? 1 : (2 in L)`, nothing ambiguous |
| `proc__return_type_failure` | parse errors: a return type on an override, `as incorrect` | the front end reports neither (no DreamChecker check) |
| `var_declare__var_redec` | `/mob/subtype redeclares var "foo"` | BYOND refuses the tree ("duplicate definition") |

The BYOND constants (`NORTH`, `WAVE_SIDEWAYS`, `FLOAT_LAYER`) are predefined macros in the compiler's preprocessor, where dreammaker
reads them as global vars. The native checker reads an expression that is exactly the expansion of such a macro written in the source
(or of a macro whose expansion is only one of them) as the constant's name (`dm-tree` `SiteMapper::invocation_output`), so the filter,
condition and range checks see what dreammaker sees: no case differs. A constant inside a larger macro's replacement is read as its
value (dreammaker would see the name); no check reads one there in the corpus or the tree.

## Accepted differences on the whole tree

Checked on the real tree and on seeded trees (2026-11-27) before the checker on dreammaker's parse was removed; every DreamChecker
diagnostic was identical. What differs comes from dreammaker's parse itself, not from a check, and is accepted:

- dreammaker's own parse diagnostics on code BYOND accepts: a parse error at `new L[1](...)` (`code/tests/benchmarks/map_plan_cost.dm`),
  and its tree finish's constant-evaluation errors (`unknown variable: GAS_ID_CHLORINE` and `GAS_ID_AMMONIA` in
  `code/domains/atmos/methane_and_fuel_gases.dm` at the time). The compiler's front end reports what BYOND reports instead, so the
  `Found N diagnostics` count is lower by those.
- The hint count (`--json` `hint`): dreammaker's `///` doc hints after `#define` are not made.
- Include paths are canonical (`code/tests/unit_tests/x.dm`), where dreammaker kept an include's own spelling (`unit_tests\x.dm`,
  `unit_tests\..\benchmarks\x.dm`).
