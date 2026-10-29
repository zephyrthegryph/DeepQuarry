# Parent-call semantic cohort

Pinned reference command, from the repository root:

```powershell
& C:/Users/bmene/SpacemanDMM/dreamchecker.exe -e tools/dmb/fixtures/unified_checks/parent_call_linear/probe.dme
```

Pinned suite-1.11 executable SHA256:
`bafd54168a539e61d8c3f71d9778e92de76d7ffbf11c693541e10be10c9633ba`.
Independent capture has three errors, in order: (2,18), (2,25), (3,12).
All messages are `proc has no parent: /datum/example/proc/probe[0/2]`.
The nested parent call inside the missing-parent call at line 3 is deliberately
not visited. Later same-owner and inherited overrides have source parents.
No reference diagnostics are filtered or suppressed.

Native source/engine parent facts use the compiler resolver. Source-only absence
is insufficient: an intrinsic ancestor can still be a parent. A full native
comparison must supply authoritative complete pinned intrinsic membership,
not the current hierarchy-only test seed. Until that input is available the
native driver must report Unsupported, not an empty diagnostic result. Unit
fixtures use a clearly synthetic complete empty engine solely to validate this
negative-proof contract; that synthetic universe is not a BYOND oracle.

The initial implementation admits linear statements, settings, returns,
missing-parent calls, group/binary/ternary/interpolation expressions and native
list/alist arguments. It explicitly refuses control-bearing blocks and argument
visitation that depends on unresolved calls/types. Source-positive parent facts
are supported without complete engine inventory. A shared pinned expression
visitation contract is needed to extend the diagnostic cohort; generic AST
walking would incorrectly diagnose unreachable expressions and arguments the
old checker never visits.

The new `native_parent_calls` oracle attaches the strict checker catalog to an
immutable native SemanticTree snapshot sharing its source backing. This supplies
exact hash-qualified fixed-DSL negatives without treating the hierarchy-only
seed as complete. After root builds the example and applies the importer/module
wiring, the independent comparison command is:

```powershell
python tools/dmb/scripts/compare_native_checker_fixture.py --reference C:/Users/bmene/SpacemanDMM/dreamchecker.exe --native <private-target>/debug/examples/native_parent_calls.exe --family proc_has_no_parent tools/dmb/fixtures/unified_checks/parent_call_linear/probe.dme
```

The comparator's family choice is in the wiring draft, not enabled until native
verification. The executable enforces this single family and refuses unsupported
contexts with nonzero exit. No comparison has run yet.
