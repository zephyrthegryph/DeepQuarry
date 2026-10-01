# Native StaticProc/DynamicProc selector evidence

This records native DreamMaker 516.1687 paired compilation and read-only VM disassembly evidence. No DreamDaemon or other DM runtime was launched.

## Paired native method metadata

The two probes differ only in whether an otherwise unused typed local is
initialized with `new` inside the callee:

```dm
/datum/caller/proc/test(datum/base/B)
    return B.action(1)
/datum/base/proc/action(value)
    var/obj/O                 // Other probe adds: = new
    return value
```

| Native record | Uninitialized local | Local initialized with `new` |
|---|---:|---:|
| Caller ProcID | 0 | 0 |
| Target ProcID | 1 | 1 |
| Caller code ListID | 41 | 37 |
| Target code ListID | 0 | 40 |
| Caller/target flags | 4 / 4 | 4 / 4 |
| Source kind / parameter | 0 / 255 | 0 / 255 |
| Argument flags / source / reserved | 0 / 32001 / 0 | 0 / 32001 / 0 |
| Class member lists | caller `[0]`, base `[1]` | caller `[0]`, base `[1]` |
| Procedure-reference table | empty | empty |
| Call selector | DynamicProc | StaticProc(1) |

The callee's code and path strings are allocated before the caller in the
DynamicProc probe, and after it in the StaticProc probe. Moving the `new` callee
declaration before the caller still produces StaticProc, so textual forward
declaration alone is not the rule. Class-typed parameters, inferred return types,
and argument-list calls also do not individually explain the selection.

The StaticProc operand is an actual **Proc table ID**, not an index into the
procedure-reference table. In the renamed/overridden probe, StaticProc(1) identifies
the base method, whose class member list contains `[1]`. Its child overrides with
Proc2, has member list `[2]`, and shares the base method's display name. An unrelated
same-identifier method has a distinct display name. Native rejects changing the
inherited display alias in the child override as a conflicting definition.

## Current full-game differences

For the 84 native StaticProc versus translated DynamicProc operand differences,
joining each native caller to its exact target path finds:

- **82** target code lists allocated later than their callers.
- **2** targets share the same deduplicated code list as their callers.
- **0** target lists allocated earlier; **0** unresolved joins.

This supports deferred native method compilation/linking as the cause of the
encoding variation. List allocation order is evidence about construction, not
an independent dispatch flag. No differing flags, alternate membership IDs, or
symbol-reference indirection was found in the paired probes.

## VM dispatch proof from the installed native binary

Binary: BYOND 516.1687 `byondcore.dll`, image base `0x10000000`, SHA-256
`4FF6F320D0C63F006F9330CF2A8DDF855EE46C2D5952AAE2A0E38E2DA9AE1AA4`.
Addresses below are virtual addresses. Export names shown by the disassembler at
large positive offsets are unrelated nearest-export labels, and are not used as
function names or evidence.

The VM reference reader starts at **0x10131030**. It advances the current frame's
instruction-word offset at `frame+0x14`, reads from the code pointer at
`frame+0x10`, subtracts `0xffcd` from the modifier, and dispatches through the
37-entry address table at **0x10131918**. Reading the PE bytes gives:

| Modifier | Actual handler |
|---|---|
| DynamicProc `0xffdd` | `0x10131371` |
| StaticProc `0xffdf` | `0x1013145d` |
| DynamicVerb `0xffde` | `0x101313fd` |
| StaticVerb `0xffe0` | `0x101314d6` |

DynamicProc reads its next word directly as a selector, then reads the argument
count. It calls **0x10133020** with mode 2 for ordinary arguments or mode 10 when
count is the `0xffff` arglist sentinel, passing the current cached receiver
(`frame+0x1c`, `frame+0x20`).

StaticProc reads the same two words, but performs this conversion first:

```text
10131466  mov (code,index,4), ecx     ; actual ProcID operand
10131476  call 10226d00              ; bounds-checked procedure descriptor lookup
10131484  mov 4(eax), edi            ; descriptor's display-name StringID
```

**0x10226d00** verifies the index against the procedure count at `0x10430c14`
and returns `index * 0x2c + [0x10430c10]`. StaticProc then passes `edi` to the
**same 0x10133020**, with the **same mode 2/10, receiver, arguments, and flags**.
It does not pass the original ProcID or its body to execution.

The shared dispatcher calls **0x10160bb0** at `0x10133063` with that selector and
receiver. This is the same receiver-tag/member resolver previously traced from
`Byond_CallProcByStrId`. The member-list scanner at **0x10161040** reads each
member ProcID, calls `0x10226d00`, and compares the selector against descriptor
`+4` at **0x10161084**. This independently establishes that `+4` is the same
name identity used by dynamic lookup. Receiver-class lookup continues through
**0x101613d0**; the final resolved ID is executed through **0x10157010**.

### Bounded semantic conclusion

For a valid StaticProc operand, replacing its selector with that referenced
procedure's effective display-name StringID yields the identical native call
resolver inputs. DynamicProc uses receiver membership, including overrides;
StaticProc is an alternate encoding of the same name selector, not a direct
base-body invocation. This conclusion applies only when the dynamic selector
bytes resolve to the referenced procedure's actual display name. Matching an
identifier spelling, canonical path, argument metadata, or unrelated same-name
method alone does not establish that condition. StaticVerb uses different
resolver modes and is not covered by this normalization.

Disassembly was saved at
`D:/opendream-diagnostic/byondcore-static-disassembly.txt`. Compile probe sources
and binaries remain under `D:/opendream-diagnostic/boundary_probe/selector_*`;
full-game target metadata is `D:/opendream-diagnostic/native-static-code-order.tsv`.
## Call versus CallStatement result handling

The VM's main opcode reader at `0x1013ea04` fetches a word from
`frame+0x10` at index `frame+0x14`. Its checked table at `0x10154278` maps
`0x29` to `0x101487e2` and `0x2a` to `0x10148848`.

Both handlers set frame flag bit 0, call the same `0x10131030` reference/call
reader, clear that frame flag afterward, and perform the same pending-yield and
exception checks. There is no additional callee dispatch flag distinguishing
the statement form. The `0x29` handler moves the result into the value stack
through `0x1016ec00`, while the `0x2a` handler skips the immediately following
word without pushing a result. A native paired method fixture confirms that
DreamMaker emits `CallStatement; Pop` for a discarded call, and `Call; Ret` for
a returned call. The skipped word in the statement form is the otherwise-needed
`Pop` opcode `0x51`.

This establishes identical invocation and external call effects for those
forms, but not arbitrary interchangeability of raw opcode sequences. In
particular, `0x29` clears the temporary evaluation value while transferring it
to the stack; `0x2a` does not perform that transfer. A comparison normalization
must establish that the result is discarded and that no subsequent instruction
reads that temporary before another expression overwrites it. Do not collapse
bare `Call` into `CallStatement`, skip branch-target validation, or normalize a
statement call not followed by the proven `Pop` word.

Native probe: `D:/opendream-diagnostic/call-result-native/probe.dme` and `.dmb`.
No runtime was executed for this investigation.
### Managed return ownership: the remaining difference is real

The dynamic reference reader writes its returned value into the evaluation slot
through `frame+0x2c` at `0x101313d9`–`0x101313eb`. It releases the previous
slot value with `0x10224810` at `0x101313ee`. This is an owned temporary, not a
borrowed return register.

`Call` transfers that temporary to the operand stack and zeros the evaluation
slot (`0x101487eb`–`0x10148810`). Its following `Pop` handler at `0x10150413`
decrements the stack count, reads the removed value, and reaches
`0x10145a0f`, which calls the same release dispatcher `0x10224810`.
`CallStatement` does neither transfer nor release: it retains the returned value
in the evaluation slot while advancing over the next word. Later replacement
of that slot releases it. Therefore the two discarded-call encodings differ
in managed-value lifetime, even when no later instruction reads the temporary.

This is confirmed beyond function naming: release dispatcher tag 15 selects
`0x10224a24`, which calls `0x10208ad0`; that function decrements a list record's
reference count at offset `+0x10` (`0x10208aea`) and, when it reaches zero under
the enabled collection condition, transfers to `0x101f89c0`. The exact
collection scheduling effects of every managed type are outside this proof.

A normalization restricted to proven unmanaged return values can avoid this
ownership difference, provided both paths also overwrite the evaluation
slot before it can be observed. Unknown or managed returns must remain a
reported difference. Identical call resolver inputs prove callee invocation,
but do not prove identical cleanup timing. No runtime was launched, and no
comparison normalization was added for this investigation.

## Implicit self-call result ownership

Compiler reference kind14 previously always emitted native `Call` (0x29), including discarded implicit method calls. Native paired positional, named, and arglist calls instead use `CallStatement` (0x2a), which retains the managed result in Eval and skips the following Pop marker. This is an actual result-lifetime distinction, established by native VM static analysis; it must not be erased by blanket Call/CallStatement normalization.

The lowerer now selects CallStatement only for an immediate unshared Pop. A bounded two-pass analysis uses the actual lowering reader and completed fixups to discover every incoming source branch, including later backedges; any branch entering that Pop requires executable Pop and therefore Call. It retries only when an incoming branch intersects a candidate marker. The same discriminator covers existing method call paths.

Native guarded safe calls intentionally use Call plus executable common Pop, and retain that form. The portable `fixtures/lowering/self_call_ownership` fixture has six caller cases: discarded positional/named/arglist, returned value, and both ternary arm positions. Both debug-mode regressions explicitly compare call opcode vectors before the semantic comparison. A separate synthetic backward-edge test preserves an executable Pop when a later edge enters it. These new tests await the shared gate; native and patched OpenDream fixture compilation passed with no warnings. DreamDaemon was not used.

## Refreshed final call category: computed receivers

The refreshed `final-parity.ndjson` reduced the call-mode category to 19 procedures after implicit self-call correction. Inspection of every pair found remaining native Call0x29 → translated CallStatement0x2a discrepancies immediately after native PopCache0x143. Computed receiver calls intentionally use Call with an executable Pop; converting them to CallStatement changes managed-result lifetime in the opposite direction. `computed_call_ownership` pairs getter-produced, conditional, short-circuit, safe and returned receivers, plus direct owner/child controls. Pending cached/computed receiver paths now preserve Call; direct references retain the native CallStatement discriminator.

CallStatement also skips exactly one raw wire word. It now emits/consumes its Pop marker immediately, preventing a source record at the OpenDream Pop offset from inserting a debug opcode between the call and marker. The deferred source records remain before the next executable instruction. Both ownership regressions verify raw decoded CallStatement/Pop adjacency in both debug modes, with multiline native-paired cases and a synthetic Pop-offset source-event case. This final batch has 7 self-call callers and 11 computed/direct callers; native/OD fixture compilation passed with no warnings, and the shared Rust gate is pending.

## Null equality and evaluation-slot cleanup

The native Null reference modifier `0xffe6` routes to `0x10131202` and calls
`0x102247e0` on `frame+0x2c`. That helper zeros both words of the owned evaluation
slot and releases its previous value through `0x10224810`. Consequently a
native `GetVar Null; Teq; Pop; GetFlag` also clears prior evaluation ownership.
The unary `IsNull` handler `0x1015098a` only replaces the top stack value with a
numeric result through `0x1013ffe8`; it does not clear that evaluation slot.

This difference can occur in legal authored source. The portable
`fixtures/translation/null_equality_ownership` pair first discards a method
returning a list, retaining it in Eval via CallStatement. It then compares
`rand(1,2)==null`, or calls `isnull(rand(1,2))`. Native PushInt and RandRange
write the numeric operand stack without overwriting Eval. The equality form
clears/releases the previous list through GetVar Null; the builtin form retains
it. Thus rewriting every authored null equality to IsNull changes managed
return lifetime. Full-game sites whose left operand is GetVar or Call may have
already cleared Eval, but that bounded observation is not a language-wide
optimizer proof. Compiler-only native pairing and static VM ownership tracing
establish this discrepancy; no runtime was launched.

## Verb namespace and static verb display conversion

The same verified DLL jump table maps DynamicVerb FFDE to101313fd and StaticVerb FFE0 to101314d6. The previous table called FFDE StaticVerb; that label was incorrect. DynamicVerb reads the selector directly and enters10133020 with mode1 (ordinary arguments) or9 (arglist). StaticVerb reads a ProcID at101314e2, calls10226d00 at101314f2, and loads descriptor+4 as the selector at10131500. It then enters the same dispatcher with identical mode1/9, cached receiver, argument pointer/count, and flags. Ordinary mode pushes are10131456 and1013154b; arglist mode pushes are1013143b and1013152b.

Thus StaticVerb can be normalized only to DynamicVerb carrying that referenced descriptor's actual display name. Proc modes2/10 remain distinct. Invalid/missing descriptors and display names retain their distinct representations. Comparator regression tests reject the wrong name, proc namespace, and missing descriptor/name.

The accepted native `verb_selectors` fixture declares a procedure and a verb with the same display name but different bodies. Native emits FFDD for the proc and FFDE for the verb with the same StringID; lowering formerly emitted FFDD for both. Resolved method and inherited bare-self calls now retain verb namespace. Existing exporter AA targets already carry the necessary procedure identity, including the fixture's untyped/computed calls; no new exporter metadata is needed.

Four additional native callers invoke a verb whose body constructs an object, forcing FFE0. They cover ordinary, safe, arglist and discarded-result calls. The integration requires these native static witnesses and translated DynamicVerb, with complete body comparisons in both debug modes. All eighteen focused bodies pass exact comparisons in both debug modes.
