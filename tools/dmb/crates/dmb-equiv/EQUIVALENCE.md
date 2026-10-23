# DMB semantic equivalence

`dmb-equiv` decides whether two compiled worlds (DMB, optionally with the RSC)
behave the same. It replaces raw-byte comparison for retained-vs-fresh native
output (incremental builds may assign IDs stably, e.g. append) and the old
structural comparator for native-vs-Dream Maker parity.

```
dmb-equiv A.dmb B.dmb [--rsc A.rsc B.rsc] [--json OUT] [--max-examples N] [--all] [--context N] [--ignore-order]
                      [--strict-order] [--ignore-debug] [--quiet]
dmb-equiv permute IN.dmb OUT.dmb [--seed N] [--tables safe|all|classes,procs,strings,...] [--keep-strings K]
dmb-equiv dump-proc FILE.dmb KEY-SUBSTRING      # canonical listing of matching procs
dmb-equiv dump-strings FILE.dmb
dmb-equiv dump-vars FILE.dmb                    # variable table: id, name
dmb-equiv global-order FILE.dmb                 # variable ids <global-init> stores to, in code order
```

Exit 0 = equivalent, 1 = different, 2 = usage/decode error. The text report
groups differences by category (`kind.family`) with readable paths; `--json`
writes the same counts and examples. `--all` lists every unexplained difference (no example cap) in both outputs. `--ignore-order` moves every table order (class, proc, variable-name) from the count to the `ordering` note, for native-vs-DreamMaker runs (user ruling 2026-10-21; runtime dumps were identical). Retained-vs-fresh checks keep orders strict. Library: `dmb_equiv::compare_bytes`,
`compare_dmbs`, `assert_equivalent_bytes` (used by dmbc's six-session tests).
DeepQuarry (58 MB DMB + 224 MB RSC) compares in about 5-12 s.

## Canonical form

Every table reference is replaced by the content it names:

| Reference | Canonical form |
| --- | --- |
| class ID (records, `path*` values, world turf/area/client/image) | type path |
| mob-table ID (tag 8, instances of kind 8, world mob) | the mob's type path |
| string ID (record fields, `Value` tag 6, Field/DynamicProc operands, Format/OutputFormat/DbgFile) | text |
| proc ID (lists, CallGlob, CallGlobalArgList, ProcPath, StaticProc/Verb, initializers) | proc key (below) |
| variable ID (declarations, locals, args, footer, `Global` operands) | name; globals by global key |
| instance ID (map grid, map objects, tag 41) | `kind:type{initializer key}` |
| resource ID | `rsc(kind:NQCRC 'first archive name')` |
| list ID | the list's decoded contents in its role |
| hidden-initializer token (tag 62) | `hidden<min site>`: tokens are compared as a partition of declaration sites |
| branch targets | `L<n>`: ordinal of the target among non-debug instructions |

Proc keys: a named body is its path; same-path bodies get `#rank`, ranked by
their anchor (owner type, verb/proc list, position in that list), which is
definition precedence. Anonymous bodies are keyed by referrer (`/T/<init>`,
`<global-init>`, `<owner>/<argN in>`), the rest by a hash of their canonical
content (identical anonymous bodies are interchangeable and compared as a set).
Same-named globals (static locals) are disambiguated by their named referencing
procs, then their default.

Equalities applied (each is a proven runtime identity, not a tolerance):

* `PushInt n` == `PushVal n` (native zero-extends the u16, FORMAT.md).
* Receiver Cache: a bare field/proc operand reads the Cache register, which
  holds `src` on entry; `a->b` sets it to `a`. Forward dataflow over the CFG
  renders every bare operand with the receiver the Cache holds on all paths
  (`GetVar .x` with Cache=src == `GetVar src->.x`); where paths disagree the
  operand stays bare and only matches another bare operand. `initial()` and
  `issaved()` wrap the whole access.
* `StaticProc/StaticVerb(id)` == `DynamicProc/Verb(display name)`: the VM
  converts the ProcID to its display StringID and dispatches by name.
* Short (<= 24 instruction) instance initializers are rendered inline where the
  instance is used (map cells, defaults, `PushVal inst`); a body of independent
  constant assignments `consts; SetVar src->.f` to distinct fields is sorted by
  field.
* Proc lists: grouped by name; only the order within a name (precedence) is kept.
* Builtin overrides: last entry wins.
* Debug stream: compared as (instruction ordinal, file in effect, line) per
  DbgLine; a DbgFile that repeats the current file or is not followed by a
  DbgLine is dropped. Debug differences are their own category
  (`proc.debug_info`) and never hide code differences; `--ignore-debug` skips them.
* Local names: compiler temporaries (`__dmb_*` native, unnamed DM) compare equal;
  slot count and order are kept.
* The header's 32-bit-ID bit (0x40000000) and the grid's run grouping are
  encoding only. Fixed-width operands without an established table role are
  compared raw (FORMAT `u` words: counts, modes, masks).

Not compared: unreferenced strings, lists, instances and procs; deleted RSC
slots, timestamps and spare capacity; table sizes.

## Encoding rules (`src/normalize.rs`)

Applied to the rendered instructions of both sides before a `proc.bytecode` difference is reported, and to type
initializers (`type.initializer_body`). Each removes a difference whose runtime effect is identical; branch targets are
renumbered after every removal. Found by reading the 2026-10-21 `a6ce3d8f16` residue (35 literal, 214 value, 67 anonymous).

| Rule | DreamMaker | Native | Why the same |
| --- | --- | --- | --- |
| Adjacent string literals | `"A"`, `"B"`, E..., `Add` (right-nested `A + (B + ...)`), also across a ternary operand and calls | `"AB"`, E... | `+` over strings is associative when A and B are string constants; E never consumes B except as an `Add` left operand (stack depth tracked) |
| Null store of a bare declaration | `PushVal null; SetVar localK` for every `var` | omitted outside loops (`typed_statements.rs`) | locals start null; the store is dead when the same straight-line code stores `localK` first, or when it is outside every backward jump with no earlier use. A declaration inside a loop or after a visible label (backward `goto`) keeps its store: native now emits it there too |
| Unreachable code | none | `Jmp` after `Ret`/`End`/`Jmp` | nothing branches to it |
| Jump to the next instruction | none | `Jmp L(i+1)` | does nothing |
| `/T::field` | `PushVal <default>` (folded) | `PushVal /T; SetVar cache; GetVar initial(src->.field)` | `initial()` is the default: checked against the class tables (nearest override, else the declaration default) |
| String operand `0x1000_0000 + id` | field names whose string id lies in 0xffcd..0xfff1 (the reserved operand words) | never allocates those ids | decoded as the plain id |
| Type initializer | procedure shared by the class and its map instances (keyed inline when short) | a separate one | compared by body; pure stores (`PushVal`/`New*`/`EmptyList`/`New` into distinct `src` fields) sort by field, constructing stores keep their order |

### Cache register model (`canon::cache_states_full`)

The receiver Cache register is modelled as a label per instruction: the canonical text of the object it holds, or unknown
when paths disagree. Writers: `SetVar cache` (the label of the value on top of the stack: a `GetVar`'s text, a call's text
`(Call ...)`, a pushed constant), `SetCacheJmpIfNull`/`SetCachePopJmpIfNull` (the value on the fall-through edge, null on the
jump edge), the receiver chain of a variable operand, and `PopCache`, which restores what `PushCache` saved on a separate
save stack. Readers render the label: bare field/proc operands and `GetVar cache`. Assumptions, each visible in DreamMaker's
own output: the register and its save stack are frame-local (a call or `New` does not touch the caller's); the registers are
read only by the operands above; a label names the object by the expression that produced it, so two encodings are equal when
they read the same labelled receivers (the compilers place the reads adjacent to the write).

### Encoding rules added 2026-10-22 (`src/normalize.rs`; all run to a fixpoint)

| Rule | Why the same |
| --- | --- |
| `GetFlag; Test` is dropped | `GetFlag` pushes the flag, `Test` pops it into the flag: no change (FORMAT.md; `IsIn; Jz`) |
| `PushCache`/`PopCache` and `GetVar X; SetVar cache` (pure `X`) are dropped | the register effect is in the labels; a `?` mark (unbalanced save stack on some path) keeps them |
| `PushCacheKey ... PopCacheKey` with no use of `cache-key`/`cache-index` and no jump between | registers unchanged across the pair |
| a jump onto a `Jmp` (any jump, case tables too), `Jz`/`Jnz` onto the same, `JmpOr` onto `JmpOr`, `JmpAnd` onto `JmpAnd`, `SetCacheJmpIfNull` onto either null guard or a `Pop` | the target certainly jumps again; the pop-or-not difference is carried by naming the target's kind |
| `GetVar .; Ret` is `End` | `End` returns `.` (`PushVal 1; SetVar .; End` is DreamMaker's `. = 1`) |
| `Switch` entries with distinct keys are sorted | exactly one case matches |
| `<global-init>` with the same statements in another order | **not hidden**: reported as `proc.global_init_order` (below) |

What is not a rule: the shapes that are not provably the same (fused range iterators, `Square`, reassociated text sums, constant
folds, safe-call evaluation order, `pick` thresholds, loop type masks, shared variables behind call receivers) were made
byte-identical in the native compiler instead (`dreammaker_shapes` tests in `dm-codegen-byond`, each measured against `dm.exe`).

### Native vs DreamMaker, production dme (2026-10-22)

`--ignore-debug --ignore-order`: 4,854 differences at the start of the lane (4,767 `proc.bytecode`, 87 `proc.proc_locals`),
0 now; the unit-test dme is at 6 differences from one cause, an untyped receiver naming a member declared on several types (147 at the start of the global-order lane). `proc.global_init_order` is proved: native reproduces
DreamMaker's initializer order (`dmbc/src/startup_order.rs`), checked here because initializers that run code can observe each other.
The checker drops code no branch reaches (entry, branch targets and fallthrough until `Ret`/`End`/`Jmp`). `dump-vars FILE --full` prints each record's
kind and value; `DQ_DUMP_GLOBAL_ORDER=FILE` makes dmbc write its computed order and ledger.

## Orders kept (runtime-observable) and dropped

Evidence comes from `tests/fixtures/order_probe.dme` (and a second probe for
overrides/proc lists, `permute --tables dup_overrides|regroup_proc_lists`) run in
DreamDaemon 516.1687: each table was permuted consistently with `dmb-equiv
permute` (3-5 seeds), the world dumps `typesof()`, `vars`, `global.vars`, verbs
and calls to `out.txt`, and the output was diffed with the unpermuted world. The
checker's verdict matched DreamDaemon in every run (45 + 33 + 2).

| Order | Kept | Evidence |
| --- | --- | --- |
| Class table | yes (`order.type_table`) | `typesof(/datum)`/`typesof(/atom)` output follows table order, including builtin types |
| Named procs in the proc table | yes (`order.proc_table`) | `typesof(/datum/mid/proc)` follows proc-table order; anonymous bodies are unreachable this way and excluded |
| StringID order of declared variable names | yes (`order.var_name_strings`) | `vars` and `global.vars` iterate by name StringID (permuting user strings reorders them) |
| Builtin string prefix (through `pixloc`, 356 strings in 516.1687) | yes, positional (`string_prefix`) | permuting any of them stops `world/New` from running; strings from 356 on (BLIND..., which Dream Maker itself shifts in DeepQuarry) permute freely |
| Proc/verb lists inside a type | yes (inside the type record) | definition precedence (FORMAT.md "Procedure membership lists"); verbs list order |
| Map objects per cell | yes | creation order |
| Equal-content RSC aliases | yes (`rsc.rsc_alias_order`) | resource-to-text returns the first inserted alias (FORMAT.md) |
| Variable, instance, mob, resource, list tables | no | permuting each leaves DreamDaemon output unchanged |
| Class declaration pair wire order | no | reversing every class's pairs changes nothing (loader re-sorts by name ID) |
| Global footer order | no | reversing it changes nothing |
| Builtin-override list order and duplicates | no, last wins | `order_probe2`: prepending a duplicate (name, 99) to every override list changes nothing |
| Proc list order across different names | no | `order_probe2`: regrouping every proc list by name changes no call result or typesof |
| Class initial-value list order | no | keyed by variable name (duplicates kept in order; not probed) |
| Whole RSC archive order | no (note only) | only alias order is observable |

Non-semantic orders are reported only with `--strict-order` (otherwise as notes).
Order differences are reported per moved element: the complement of a longest
increasing subsequence, so one appended type is one difference, not thousands.

Consequence for incremental output: appending a new type, a new named proc or
a new variable-name string at the end of its table is observable whenever a
fresh build would place it earlier (typesof/vars iteration order). The checker
reports those as `order.*` differences; they are real behaviour differences.

## Validation

* `cargo test -p dmb-equiv`: identical and round-tripped worlds are equivalent;
  `--tables safe` renumbering (all tables, observable orders preserved; 8 seeds)
  is equivalent; unobservable single-table permutations are equivalent; class,
  proc and string permutations report only `order.*`; one changed default, one
  changed opcode, one changed string, and an edit inside a renumbered world are
  each reported as exactly one difference at the right path/statement.
* DeepQuarry native build and Dream Maker build: self = equivalent;
  `permute --tables safe` = equivalent (several seeds); `--tables all` reports
  only `order.*` and `string_prefix`.
* dmbc `six_session` tests assert retained-vs-fresh equivalence (13 pass).

## Native vs Dream Maker baseline (DeepQuarry test build)

`baseline/dm-vs-native-deepquarry.json`: Dream Maker 516.1687 (`-DCBT
-DCIBUILDING -DCITESTING -DDEBUG`) vs native dmbc from `dmb/takeover` 4e53b4badd
on the takeover baseline source. 147,854 differences (the old structural
comparator reported 0.5-1.9M, mostly ID/order noise):

| Category | Count | Triage |
| --- | ---: | --- |
| `proc.debug_info` | 47,512 | real: native emits a trailing DbgLine for the implicit return (20k), DM leaves the file unset in `<init>` bodies (12k), native lines are one lower than DM's (15k) |
| `order.proc_table` | 40,836 | real: native puts builtin procs first and orders user procs differently; `typesof(/T/proc)` order differs |
| `order.type_table` | 32,989 | real: native emits builtin types first; `typesof()` order differs |
| `proc.bytecode` | 13,434 | real codegen differences; signatures in the JSON. Top: `GetVar null-ref` vs `PushVal null` (5,370; fixed: native now reads an authored null through the Null reader, as DreamMaker does, and pushes a null only for omitted arguments and padding), constant values differ (1,204, e.g. `16777215` vs `0`, `196351` vs `262143`: likely native constant-folding bugs), fused `Jz` vs `GetFlag; Jz` (971), assertion `Format` vs `JmpOr` shapes (793), epilogue `End` vs `Jmp`/`PushVal 0` (794), IterLoad type filter `291`/`3` vs `0` (250: native drops the `for(var/T/x in L)` filter), fused `IterLoad` over view/range vs explicit call (~400), `PushCache` reuse (191), `/atom` path tag 10 vs 9 (94), `NewImage` vs `NewImageArgs` (87), class `<init>` assignment order |
| `order.var_name_strings` | 12,921 | real: var-name StringIDs ordered differently, so `vars` iteration order differs |
| `proc.proc_locals` | 94 | real: native allocates extra temporaries |
| `type.type_appearance` | 58 | real: native writes `""` where DM writes null (icon_state/name/text) |
| `type.type_mob`, `type.type_verbs`, `header`, `proc.proc_args` | 10 | real: compact sight byte 164 vs 128, verb list order, compatibility line `v516 516` vs `v515 468`, an argument `as` mask missing NULL |

Checker gaps found and closed while building the baseline (each was a large
false-difference source): bare-Cache receivers (~20k), static vs dynamic
calls, instance-initializer identity cascades (map cells, defaults,
missing/extra anonymous procs), DbgFile repetition, override duplicates, proc
list order across names, temporary local names. No remaining category is known
to be a checker artefact; the debug-line convention and the extended mob sight
byte are the least certain.

## Probe procedure

```
dm.exe order_probe.dme && dd.exe order_probe.dmb -trusted -invisible   # writes out.txt
dmb-equiv permute order_probe.dmb p/order_probe.dmb --seed 1 --tables procs --keep-strings 437
(cd p && dd.exe order_probe.dmb -trusted -invisible) && diff out.txt p/out.txt
dmb-equiv order_probe.dmb p/order_probe.dmb
```
