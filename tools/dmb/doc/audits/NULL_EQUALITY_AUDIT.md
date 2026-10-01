# Null equality and interpreter ownership

## Scope

This audit covers all 30 `equality_flag_with_short_circuit_candidate` pairs in
`D:/opendream-diagnostic/final-parity.ndjson`, compared against the matched native
516.1687 game. It classifies the null rewrites inside those procedures, not every
other difference in their bodies. No blanket null-equality normalization was
added to the comparator.

There are 39 native equality-to-null sites: 37 materialized boolean results and
two direct conditional results. Four additional null-inequality rewrites occur
in the checkers and integrated-circuit-printer procedures; these are separate
from the 39 equality sites. All four read an indexed value after a variable
read, then compare it to null with `Tne`. Their boolean result is consumed by
short-circuit evaluation or `Test`; the optimized `IsNull; Not` has the same
truth result. They have the same clear-scratch producer pattern described below.
These extra sites were inspected directly rather than included in the 37-site
flag-liveness and 39-site incoming-edge totals.

## Boolean and control-flow evidence

The materialized native sequence is `GetVar Null; Teq; Pop; GetFlag`, whereas the
optimized output uses `IsNull`. The two native direct conditional sequences use
`GetVar Null; Teq; Pop; Jz`; their replacements use `IsNull; Test; Jz`.

The native equality helper at `1024ccd0` compares value tag and payload. A
canonical null therefore has the same truth result as the tag-zero test in
`IsNull` (`1015098a`). `Teq` writes the frame flag; `IsNull` does not. All 37
materialized sites were checked for subsequent flag reads: every path overwrites
the flag or ends the procedure first. In particular, `IterNext` resets the flag
at `10147320`. The two direct conditional replacements explicitly restore it
with `Test`. No incoming branch enters a removed sequence interior at any of the
39 sites.

The first following instructions at those sites are 12 `Jnz` short-circuit,
seven `Jz` short-circuit, 15 `Test`, two ordinary conditional jumps, one return,
one variable read, and one constant push. Short-circuit instructions inspect the
stack value, not the frame flag.

## Ownership evidence and its limit

Boolean equivalence alone is insufficient. The native null variable reader
clears the interpreter's managed Eval scratch. Replacing it with `IsNull` can
change when an earlier retained value is released.

For these 39 observed sites the scratch is already clear:

- 34 tested values immediately follow `GetVar`, which clears the Eval scratch
  at `10145e23`.
- One follows `Call` (opcode `29`), whose normal return path leaves the scratch
  clear after the transfer at `10148808`.
- Four follow list indexing. Each has a preceding `GetVar`, followed only by
  list indexing or a string constant push. `ListGet` uses the separate
  `[ebp-220/-21c]` scratch and writes its result directly to the stack; it does
  not refill the Eval scratch `[ebp-218/-214]`. The four sites are checkers
  `can_jump_piece`, checkers `generate_valid_moves`, chess `can_move_piece`, and
  NIF `tgui_act`.

This establishes bounded equivalence for the 39 equality rewrites with respect
to boolean result, flag use, branch entry, and this ownership difference. It
does not establish equivalence for arbitrary equality-to-null expressions.

## Concrete counterexample outside these sites

Native compilation of `O.managed(); return rand(1,2)==null`, where `managed()`
returns a list, retains that list in Eval after the discarded method call.
`RandRange` does not clear it; the native null reader then releases it.
Authored `isnull(rand(1,2))` omits that release. The OpenDream equality-to-null
optimizer conflated these authored expressions. Removing that optimization also
exposed a lowering defect: a direct comparison's null operand was emitted as
`PushVal Null`, which omits the native null reader's Eval release. The lowerer
now uses optional post-optimizer `NativeNullOffsets` provenance to emit
`GetVar Null` at the authored null load, including reversed and conditional
operands. Synthetic null padding remains separate, and packed switch keys remain
embedded table values rather than executed loads. The
compiler fix and paired regression preserve the distinction; a comparison rule that blindly treats
the two sequences as equal would conceal this defect.

Diagnostic evidence is under `D:/opendream-diagnostic/`: the candidate pair
table, `null_equality_shape.txt`, `null_flag_liveness.txt` (37/37 flag proofs),
native static disassembly scripts, and `null-scratch-ownership/probe.dm`.
DreamDaemon was not run.

The portable regression is `fixtures/translation/null_equality_ownership/`.
`translate::tests::null_equality_preserves_native_eval_cleanup` checks all 31
authored global procedure identities in both debug modes, compares complete
native bodies, and additionally checks actual comparison versus `IsNull`
opcodes and the native Null-reader counts. It covers reversed and conditional
operands, parentheses, negative/branch contexts, returns, global/local/field
assignment, lists, call arguments, interpolation, and packed switch keys.
Literal comparisons retain native runtime comparison and null-load ownership effects. Global/local const-null aliases use native readonly Global bindings. Four constructor contexts cover sound, image, icon and new.
