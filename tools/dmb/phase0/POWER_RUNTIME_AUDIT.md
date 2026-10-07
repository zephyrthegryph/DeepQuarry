# Frozen power runtime discrepancy

This is a static audit of the frozen Phase 0 pair. No runtime was launched and no
source or binary was changed. It does not establish runtime causality or parity.

## Inputs and provenance

The matching source is
`D:/dmb-native-v2-phase0/frozen/source/code/modules/power/power_bridge.dm`,
SHA256 `32d0500e305ec68d0b85f943ba5f0ae79f1aee3e65b803daf7a3646a6a4921e3`.
Its line154 is the retired-event branch's
`power_regions[events[at]]`. The current checkout's line numbering is not an
authority for this failure.

The binaries are `D:/dmb-native-v2-phase0/frozen/pairs/{byond,native}/world.dmb`:

| Producer | SHA256 |
|---|---|
| BYOND | `8ff8911a26547da3e2cb49daa185b45cc723b4fc2f73d4cbc48efa43f20e5775` |
| Preserved native | `174359e9e849bdd610043f5879bbb781c35d406fe92142b295f822d19130a6ed` |

[power-static-followup.json](power-static-followup.json) binds the individual
decoded procedure dumps, class records, construction chains, and their hashes.
[power-rootcause.json](power-rootcause.json) binds the raw logs and FFI evidence.

## What the static comparison establishes

After renaming string/local/table identities, both `process_power` bodies read
Src.power_regions, local.events and local.at, then execute two consecutive
ListGet operations. BYOND proc 4177 has DbgLine 154 at 0x13b, inner access 0x147 and
outer access 0x148. Native proc 33419 selects kind 3 at 0x112 and executes the same
read shape at0x116–0x121. Either nested access can raise the reported bounds
error; the logs do not expose the operands or identify which access failed.

`power_facade` reads regions[id] before any capacity growth. The key allocator
explicitly grows a different list, key_objects. This is a source-level bounds
candidate; the actual id, list length and receiver state are unknown.

The serialized regions defaults differ: BYOND kind 62/payload 380 versus native
Null. Both machines class records bind their own initializer, and both decoded
initializers allocate an empty list and set this field. Present constructor
dispatch and initializer bindings do not prove VM invocation timing or final
receiver state. The frozen Master random_seed uses shared storage under BYOND
and Src-field storage under native: a concrete semantic difference whose power
causality is unproved. Current compiler fixes must not be credited as the cause
or repair of this frozen discrepancy without a new controlled comparison.

FFI wrapper library/function strings agree, but returned event values were not
captured. The frozen DLL exposes an older interface absent from the frozen Rust
source. Header/compatibility differences also remain hypotheses.

## Runtime reporting is not runtime parity

The raw files are
`D:/dmb-native-v2-phase0/frozen/preserved/{byond,native}/runtime-errors.log`.

| Producer | Bounds records | Blank-origin bounds records | SHA256 |
|---|---:|---:|---|
| BYOND | 3,087,060 | 0 | `8b4871f6e31d434b8fef96efddeea4e96a6114cab9efa9dfc8966483ded87697` |
| Native | 3,068,028 | 3,068,028 | `2702c0c052b431573052951b1dfca27d0f9905a73b3b5315575cb96a26430054` |

BYOND attributes 1,099 records to line 85, 1,099 to 107, 117 to 154 and 111 to 151.
The earlier 85/107 startup errors precede the later retired-branch failures.
Native's raw bounds records lack source locations. Similar totals do not prove
event correspondence, and unlocated errors cannot be assigned to this proc.
Missing origins also affect erroruid/cooldown routing and per-test reporting.
The nine apparent BYOND-only test failures therefore do not prove the native
program avoided these runtime errors.

Reproduce these raw-record counts with streaming readers, not a full JSON load:

```powershell
rg -c 'list index out of bounds' D:/dmb-native-v2-phase0/frozen/preserved/byond/runtime-errors.log
rg -c 'list index out of bounds' D:/dmb-native-v2-phase0/frozen/preserved/native/runtime-errors.log
rg -c '^[0-9:]+ : list index out of bounds\r?$' D:/dmb-native-v2-phase0/frozen/preserved/native/runtime-errors.log
rg -c 'power_bridge\.dm:154 list index out of bounds' D:/dmb-native-v2-phase0/frozen/preserved/byond/runtime-errors.log
```

These commands count one selected raw channel. Do not add its counts to
structured events as if the two channels were disjoint or complete.

## Stage 0 acceptance correction

### Current source inspection after review cleanup

The frozen `var/static/random_seed` storage mismatch is a definite historical
semantic divergence: two Master constructions can repeat initialization with
instance storage, whereas BYOND retains one shared seed. Its connection to the
power bounds errors is still unproved. The current compiler's source carries
the static declaration flag through `adapter.rs` and `variable_facts.rs` into
a shared slot; `simple.rs` resolves that slot before the instance-field fallback,
and `lower_resolver.rs` records the global dependency. This inspection does not
prove the newly emitted binary is repaired; a controlled output comparison is
still required. Current nested indexing emits ordinary consecutive `LIST_GET`
operations and does not suppress bounds errors. No current power-error cause
was established by this inspection.

Every unlocated runtime error remains comparison evidence. It is an unresolved
coverage/ownership gap, never a false pass or proof of improved correctness.
Preserve raw and structured channels separately, report unmatched/unlocated
counts, and require source-aware emitted debug data before interpreting
per-test exception parity. Closing this case requires controlled source-aware
runtime evidence of receiver state and event operands; opcode presence alone
does not close it.
