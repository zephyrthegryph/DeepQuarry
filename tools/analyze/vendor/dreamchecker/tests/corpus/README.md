# DreamChecker corpus

The oracle for porting DreamChecker onto the compiler front end's tree (`doc/rewrite/proposals/lean_unified.md`, "2b DREAMCHECKER").

- `cases/*.dm`: one project file each. `<suite>__<test>.dm` are the vendored crate's own test snippets (`tests/*.rs` before the
  port); `seed__*.dm` make every other DreamChecker diagnostic kind fire (control flow, settings and directives, static types and
  fields, sleep and purity call trees, filters, keyword arguments, BYOND constants).
- `expected/<case>.txt`: every diagnostic DreamChecker registers on dreammaker's parse (every severity, line and column, error type,
  notes), as `dq_analyze::dreamchecker::render` prints it. Recorded with `DQ_DC_CORPUS_BLESS=1`.
- `expected/<case>.dmbc.txt`: the native checker's output where it differs on purpose (`DQ_DC_CORPUS_BLESS_NATIVE=1`). Every such
  file is listed below with its reason. None of them is a DreamChecker check reading the tree differently: each is a parse.

`tools/analyze/tests/dreamchecker_corpus.rs` runs both checkers on every case, serial and on three threads.

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
