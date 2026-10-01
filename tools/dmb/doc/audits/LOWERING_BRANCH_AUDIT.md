# Closed branch operand lowering audit

Native BYOND 516.1687 and the pinned patched OpenDream compiler accept every source in these portable fixtures without errors or warnings. DreamDaemon was not used.

| Fixture | Previously rejected legal shape | Native shape preserved |
|---|---|---|
| `fixtures/lowering/multidimensional_branches` | Short-circuit and nested conditional dimensions | List type precedes evaluated dimensions; every internal branch remains inside its dimension |
| `fixtures/lowering/prompt_branches` | Conditional choice list and conditional text arguments | Choice list precedes native prompt arguments; argument-local joins move with their expression |
| `fixtures/lowering/range_pick_branches` | Conditional/short-circuit membership bounds and weighted-pick operands | Range bounds precede value; weighted pick evaluates weights then only the selected candidate |
| `fixtures/lowering/output_branches` | Conditional output RHS, computed field owner, indexed target | Receiver resolves before RHS; indexed target uses native Index before output |
| `fixtures/lowering/self_arglist` | Current-proc conditional arglist call | Native CallSelfArgList; existing parent CallParentArgList remains covered |

The last completed core snapshot passed these paired fixture tests, including prompt provenance/default-null and current-proc arglist calls. The expanded 144-procedure prompt union matrix also passed in both debug modes. The conditional Initial/IsSaved index cases also pass the refreshed core run.

## Preserved original multidimensional evidence

The initial `var/list/L[n || 2][n && 4]; return L` fixture lowered its dimension expressions correctly after the span fix, but exact comparison exposed an existing local-store result optimization: native `SetVar Local; GetVar Local; Ret` versus translated `SetVarExpr Local; Ret`. Both assign the same local and return the assigned value. This bounded local pattern is harmless; it is not a general claim about instruction-count differences. The portable exact regression returns `L.len` to isolate dimension evaluation and branch relocation from that optimization.

## Proof boundary

Reordering accepts only verified closed expression spans. Every branch target within an argument must stay within that same argument, and outside branches cannot enter its middle. Internal branch slots and end joins move with the expression; unproved/nonlocal shapes retain explicit errors.

Explicit `input ... as anything` is distinct from an omitted type in native bytecode (`0x1000` versus zero). The pinned compiler now preserves authored-anything provenance in bit31 of the Prompt type operand; the Rust lowerer strips that metadata bit and applies the native type flag. No opcode size changes are required.

Prompt bit30 separately records an authored choice expression, including
`in null`; supplied choices set the native choice flag even when their value
is null. These provenance bits describe syntax and are stripped during lowering.

`fixtures/lowering/initial_saved_branches` adds closed conditional list owners
and keys for Initial/IsSaved without reordering operands. Outside-entry and
cross-expression branches retain the same rejection boundary.

## Implicit self-call managed result ownership

Native static compilation of `fixtures/lowering/self_call_ownership` distinguishes discarded implicit method calls (`CallStatement` 0x2a followed by its Pop skip marker) from value calls (`Call` 0x29). The lowerer previously always emitted 0x29 for compiler reference kind14. It now uses 0x2a only when the immediate OD Pop has no other branch entry; a shared ternary join retains 0x29 and the executable Pop. Seven exact caller regressions cover positional, named, arglist, returned value, and both ternary arm positions, in both debug modes. Tests explicitly compare call opcode vectors in addition to the semantic comparator, preventing call-mode normalization from hiding the distinction. Native VM static analysis of result ownership is recorded by the input agent; DreamDaemon was not used.

## Conditional Initial/IsSaved indexed operands

`fixtures/lowering/initial_saved_branches` contains eight accepted native/OD procedures with conditional or short-circuit list/key expressions. Existing closed-diamond analysis now recognizes the two stacked operands; their source order and internal branch destinations remain unchanged before native CacheIndex consumption. Both debug modes require exact normalized procedure agreement.

The native void-result helper now shares the same all-incoming Pop analysis. A later branch entering a previously consumed Pop forces a retry that materializes the void expression's null value and retains the executable Pop. Eleven helper call sites use this check. A synthetic `rand_seed` regression verifies both the ordinary consumed-Pop form and the backward-edge form, including the destination's stack value. Both forms pass the refreshed core run.

## Protected-body joins at EndTry

The full-game `safe_file2text` comparison exposed an ordinary if/else join
incorrectly converted from Jmp to TryJmp. The target is the exact OpenDream
EndTry boundary, which lowers to the native Catch cleanup instruction. This
boundary belongs to the protected body's normal exit; only destinations beyond
it require the separate protected-exit conversion. Lowering now includes that
boundary when checking whether a jump leaves its region.

Native VM handlers at `1015048a` (Catch) and `101504dc` (TryJmp) both check the
linked exception-frame ranges, but follow distinct dispatch paths. The repair
preserves the actual native opcode rather than assuming their cleanup and
scheduling behavior interchangeable. `fixtures/translation/try_join_cleanup`
contains five paired callers: ordinary and nested conditionals, nested try,
ternary arguments, and a genuine outward goto. The integration test compares
complete bodies in both debug modes and separately asserts exception opcode
sequences. Its combined package gate passes.

## Authored protected loop and goto branches

A final full-game planner audit exposed a boundary that layout inference cannot recover after the OpenDream optimizer removes unreachable loop tails. Native TryJmp checks destination minus one against exception frame ranges. A continue/goto to the first protected word therefore removes that frame; ordinary JmpLoop/Jmp retains it. Forward goto also uses TryJmp's loop-budget dispatch, even when it retains the frame.

The native Try handler at 1015042f..10150485 stores the first protected word and catch destination as frame bounds. TryJmp at 101504dc..10150524 performs the range check and enters 10150210; Catch at 1015048a..101504d7 performs the range check and enters ordinary dispatch at 1015387d.

Optional optimized-source NativeTryContinueOffsets, NativeTryBreakOffsets, and NativeTryGotoOffsets identify authored protected branches. The lowerer restores TryJmp/Catch before target relocation, while ordinary loop tails remain JmpLoop. The portable nine-case fixture covers first-word and prefixed heads, nested try, indexed iteration, break, forward/backward goto, and unprotected goto. All nine provenance cases and the existing five TryJoin cases pass in both debug modes. The combined 503-test package gate passes.

## Authored forward goto budget dispatch

Fresh native compile-only probes establish authored goto uses F8 JmpLoop in both directions, including target immediately following the branch; protected goto remains12F. Native F8 enters10150210, decrements frame budget+0x6c, and evaluates scheduling/time checks on exhaustion. Ordinary0F bypasses that work. NativeGotoOffsets preserves all authored optimizedGotoJump provenance, with protected NativeTryGotoOffsets overriding to12F. Portable goto_budget fixtures cover nine branch/control cases. Native evidence complete; focused native comparisons and the combined 503-test package gate pass.

## Synthetic loop join budget correction

Native while-if/else synthetic join is ordinary0F even when its target is the finalF8 natural loop back. The old forward-continue heuristic incorrectly emittedF8 for that join, creating an extra CPU-budget check. NativeContinueOffsets Some([])/Some(offsets) source provenance now distinguishes no authored continue from legacy absent metadata; protectedTryContinue retains12F. Four nativepairedcontinue_budget cases establish exact budget counts/directions/destination executable opcodes. Focused native comparisons and the combined 503-test package gate pass.

## Lazy unweighted pick

Native multiargument `pick(a, b, ...)` dispatches before evaluating its alternatives. OpenDream's eager candidate stack cannot be preserved through `NewList; Pick`: an unselected function call, mutation, or runtime must never execute. Lowering now moves verified closed candidate expressions behind native PickSwitch79 and relocates their internal branches. Singleargument `pick(list)` retains native PickD2.

Compile-only native probes establish cumulative thresholds `i * floor(65535 / count)`: four alternatives use16383/32766/49149 rather than32767/49151. Native also accepts300 alternatives. Count validation is bounded by available source bytes, including the packed numeric operand stream, rather than an artificial255 limit.

The portable `pick_unweighted_lazy` fixture compares complete native/translated procedure bodies in both debug modes. It covers calls, conditional/short-circuit and safe candidates, nested picks, call arguments, iterators, repeated/computed field receivers, and all299 table thresholds of a300-candidate pick. Its18-case focused standalone integration passes. The full-game audit passes all59,982 procedures after adding the Prob unary stack contract and preserving existing external joins at a new dispatch table. The final22-case expansion passes complete native body comparisons in both debug modes, adding adjacent dispatch tables and300 string/resource/global-reference candidates. The combined 503-test package gate passes.

The closed-expression span verifier also recognizes weighted PickSwitch/PickProb, including nested probability expressions. Registered internal table/join fixups participate in later relocation and cache branch entry analysis. The18-case cache_pick_freeze native comparisons pass both debug modes, including nested weighted candidates and side-effectful probability receiver changes.

## Do/while final-condition budget checks

Fresh mixed-body inspection found27 native F9 JnzLoop instances represented as translated Jz(exit);F8(backedge). Installed516.1687 VM table10154278 maps F9 to10150284. Both true/false outcomes reach budget decrement1015029f, whereas ordinary Jz(101502ed) bypasses it. The split therefore misses the final false budget check. Authored conditional goto retains Jz+F8 natively, so a generic adjacency peephole would be wrong.

Optimized-source NativeDoWhileConditionOffsets identifies only nonconstant authored do/while conditions; lowering handles JumpIfFalse and JumpIfFalseReference, validates the paired natural backedge/exit, and restores F9. Native constantfalse/null tails are removed by the exporter, preserving the absence of an authored Null-reader eval release; constanttrue retains the natural F8 backedge. All16 paired complete bodies pass both debug modes, including protected loops/continue, iterator frames, nested/effectful conditions, localconstant aliases, and unrelated conditional goto/ordinary while negative controls. No runtime was executed. The full game needs a fresh export/emission before the residual27 can be declared eliminated.
