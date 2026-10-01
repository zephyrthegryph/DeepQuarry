# Generated procedure parity audit

The original matched full-game outputs contain 62,325 native procedure records
and 62,318 translated records. The seven-record reduction is initializer reuse,
not seven missing implementations.

| Anonymous procedure role | Native | Translated |
| --- | ---: | ---: |
| Argument value sources | 110 | 110 |
| Class initializers | 12,270 | 12,270 |
| Instance initializers | 2,750 | 2,743 |
| Global initializer | 1 | 1 |

All instance initializers decode as independent constant assignments after
removing source file/line markers. Both outputs contain the same **2,743 distinct
assignment bodies**. Four bodies account for all seven fewer procedure records:

| Assigned accessory | Native procedure IDs | Translated procedure ID | Reduction |
| --- | --- | --- | ---: |
| `/obj/item/clothing/accessory/scarf/white` | 62318, 62323 | 59578 | 1 |
| `/obj/item/clothing/accessory/holster/hip` | 62287, 62317, 62319, 62324 | 59576 | 3 |
| `/obj/item/clothing/accessory/wcoat` | 62288, 62289, 62315 | 59575 | 2 |
| `/obj/item/clothing/accessory/sweater/blackneck` | 62286, 62316 | 59577 | 1 |

Each body assigns `starting_accessories` to the same ordered, one-element list.
The native copies differ in source markers; the translated bodies are shared.
This changes allocation and debugging information, while preserving the observed
initialization values and per-execution list construction.

## Shadowed carpet prototype

Native instance 14 is `/obj/item/stack/tile/carpet/purcarpet{amount = 20}`.
Its only reference is an earlier `object_type_to_spawn` initializer in
`/datum/maint_recycler_vendor_entry/DIY_Carpet_purple` (native class 11560,
variable 13120). The same native class initializer list subsequently assigns
instance 15, `/obj/item/stack/tile/carpet/purplecarpet{amount = 20}`, to that field.

The source repeats this type at lines 200 and 244 of
`code/modules/maint_recycler/code/vendor_datums/entries/hangout_entries.dm`.
The later definition wins. No procedure, variable record, or map refers to
instance 14. Its absence from the translated output therefore removes a
superseded constant rather than the effective vendor item.

## Instance record count

The nine fewer instance records consist of seven duplicate constant prototypes,
the shadowed carpet prototype above, and one plain image prototype discussed
below. The duplicate prototypes are:

- Two identical CentCom airlocks with `req_one_access = list()` become one.
- Two white uniforms with a white scarf become one.
- Two pants prototypes with a hip holster become one.
- Two PCRC uniform prototypes with a hip holster become one.
- Three suit jacket prototypes with a waistcoat become one.
- Two pants prototypes with a black sweater become one.

Every constant override value, type identity, and ordered list element in those
duplicates matches. The plain native image prototype is instance 11629,
`/mutable_appearance/appearance_mirror`, kind 63. It has no explicit procedure,
variable record, class initial value, or map reference; its class remains present.
The emitter now allocates plain prototypes for all mutable-appearance descendants, restoring this record. A native paired parent/child fixture validates kind-63 allocation, constructor resolution, and serialized round-trip.

## Reproduce

Build `cargo build --manifest-path tools/dmb/Cargo.toml --example proc_inventory`.
Run the executable with native DMB, translated DMB, output NDJSON, and optionally
a native instance ID to inspect references. The audit artifact is
`D:\opendream-diagnostic\generated-proc-inventory.ndjson`.

The comparison resolves type and field identities, preserves ordered list
contents, and compares independent constant overrides irrespective of assignment
order. Effectful or nested modified-type initializers remain opaque. This audit
does not establish full runtime parity.
## Variable-record follow-up

The native table has 121 more variable records than the previous translation.
Of these, 119 are duplicate null/name records across 91 names. Ownership,
argument, local and global declaration references are present; this portion of
the count gap does not represent missing variables. The other two native records
are `vars`, kind 82: one is referenced by native `GetVar(Global VariableID)` and
one is unused. The earlier translation emitted the intrinsic as a literal value
instead of this special variable read. Evidence is recorded in
`D:/opendream-diagnostic/variable-record-differences.txt`.
