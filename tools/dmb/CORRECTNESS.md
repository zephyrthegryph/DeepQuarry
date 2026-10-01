# Offline compiler correctness gates

These tools inspect existing outputs and captured logs. They never launch
DreamDaemon. Passing structural checks does not prove execution equivalence;
the runtime suite remains the integration gate.

## Compiled output gate

```text
cargo build -p byond-dmb --example correctness_gate -j1
correctness_gate EXPECTED.dmb ACTUAL.dmb report.json [--canonical] [--instructions] [PATH_PREFIX...]
```

`--canonical` additionally requires identical complete DMB bytes. The default
compares selected metadata and normalized procedure code, with resolved lossless
table identities, normalized compact numeric pushes, and instruction-index branch
destinations. Argument counts, local slots, dynamic selectors and unknown immediate
words remain observable. Named procedures, duplicate definitions in owning-binding
order, class/world initializers and argument-source helpers participate. Whole-world
selections check map records too. Empty selections and decoding errors fail.

Changed bodies align by opcode, preferring exact operands. Inserted instructions
therefore do not make every subsequent row a positional mismatch. Local shifts and
branch changes remain recorded, and the original normalized instructions decide
the gate. Changed regions describe encoding differences, not independent bugs.
Alignment uses at most one million cells (4 MB); larger bodies fall back to one
bounded prefix/suffix region. `--instructions` includes complete normalized bodies
for changed procedures. `path_bytes` disambiguates non-UTF-8 display labels.

Native and Rust compilers can use different switch, temporary-local or receiver
encodings. Inspect aligned differences and reduce a suspected defect into a native
fixture before treating it as a compiler regression.

## Captured diagnostic gate

```text
python dev-scripts/correctness_reports.py \
  --expected-compile native-build.log --actual-compile rust-build.log \
  --expected-compile-exit 0 --actual-compile-exit 0 \
  --expected-runtime native-runtime.log --actual-runtime rust-runtime.log \
  --expected-tests native-unit_tests.json --actual-tests rust-unit_tests.json \
  --output report.json
```

Provide any complete pair. Compiler gates require captured exit codes: no parsed
errors alone cannot establish successful compilation. Reports retain exact error
codes/messages, shared failures, new failures, missing/extra tests and count changes.
`--fail-on-count-increase` adds a count gate.

Runtime logs are streamed, including UTF-16 captures. Procedure paths identify
errors when available, then source files. Unlocated messages remain ambiguous;
matching text cannot assign them to a source. Aggregate message counts and new
messages remain available. Incomplete attribution fails the gate without turning
every missing location into a new regression. Supply runtime-errors captures or
test runner `Runtime in ...` lines, since arbitrary timestamped server messages can
resemble error headers.

Whole-run errors and per-test failure messages have different scopes. An error
printed for one compiler's failing test but absent from another compiler's passing
test line does not establish whole-run error absence.

## Small compiler and cache gates

```text
cargo test -p byond-dmb --lib compare::tests -j1
python dev-scripts/test_correctness_reports.py
cargo test -p dm-compiler --test correctness_gates --test fingerprint_stages -j1
```

Compiler fixtures create disposable projects outside Git; unset
`DM_COMPILER_CACHE_ROOT` to protect shared caches. Canonical assembly retains one
frontend session and compares full DMB and nonempty RSC bytes with an independent
empty-cache project after body edits, procedure/variable additions, type/default/
inheritance/static changes, negative static-member resolution,
deletions, assets and reverts. A separate legacy body-patch regression gate checks
normalized output against fresh assembly. The numeric list fixture's native output
was compiled offline with BYOND 516.1687; it was never hosted.

| Cache | Implementation fingerprint |
|---|---|
| Procedure syntax pack | Syntax/parser, parse pack codec, relevant locked codec/hash dependencies |
| Symbolic lowering | Syntax/codegen/IR/semantics, binding adapters, witnesses, worker transport, store, bytecode/operands and opcode registry/generator |
| Frontend/checkpoint | Broad compiler/frontend/map/resource/backend implementation and complete lockfile |

Backend/output changes preserve syntax packs. Binding adapters still share modules
with emission, so those edits conservatively invalidate lowering. Unknown compiler
modules are included unless explicitly classified as producers/output-only. Locked
dependency closures retain versions/checksums/transitive dependencies; unknown
formats fall back to the complete lockfile.

## Statement source attribution

Symbolic procedures carry body-relative statement anchors, including basic-block
entries. Linking resolves them against the current preprocessed source origin map
and inserts `DbgFile`/`DbgLine` before instruction relocation. A cached procedure
contains no absolute source offsets or stale filenames. Uniform movement before a
procedure preserves its anchor shape; changed locations inside its body invalidate
the lowering memo. Synthetic code without a real source anchor remains explicitly
unlocated. Locations identify statements, rather than every subexpression of a
multiline expression. Offline tests check rebasing, branch targets and decoded
debug instructions; runtime attribution still needs a future integration run.

Lowering errors carry optional body-relative statement spans, attached before
nested lowering restores its caller's source context. Link-time type failures can
locate the original symbolic reference through `debug::reference_origin` before
instrumentation. Missing default-argument anchors use a separately captured real
authored header; error locations are never guessed by searching statement text.

## Frozen power error investigation

Artifacts: `full-suite-comparison-dcd1b1f39fe14bd6a3ad65fd8d2bc1da`, native
`source-final/comparison.dmb`, Rust generation
`2be3e35918c9bd4cc7f90b0ad9c71e55655e61f604584e60085d446fbdbc9fbc/world.dmb`.
The frozen source predates independent game changes.

`/datum/controller/subsystem/machines/process_power` is native procedure 4177 and
Rust procedure 33419, with 186 and 223 normalized instructions. The initial positional
comparison reported 234 differences; switch/local shifts made that count cascade.

The retired-region access has the same inputs and operations:

```text
Get src.power_regions
Get events (local 1)
Get at (local 7)
Index (0x7b)
Index (0x7b)
Store network (native local 10; Rust local 11 after its switch temporary)
```

Both execute `power_regions[events[at]]`. The reduced fixture matches native code.
Missing numeric indices use positional list semantics; using numeric region IDs
as keys in an empty list is a plausible game-source cause. Background ownership
timing is another unproven explanation for changed test failure attribution. This
investigation establishes no compiler root-cause fix.

The native main raw capture has 1327 sourceful power index errors across lines 85,
151,154. Rust has 3068028 unlocated index errors mixed with lifecycle flooding,
without source/proc stacks. Rust line 154 presence/absence cannot be proved from
that capture. Native all-source index errors total 3087060. The suite wrapper's 15
native power errors are per-test failure attribution, a different scope. No new
server run or game-source modification was used for this investigation.
