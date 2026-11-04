# Capability contributions: `CAPABILITIES_PART(T, feature)`

Status: implemented. Approved by the user as a change to the one-root-per-type rule (doc §1).

## Problem

A type had exactly one `CAPABILITIES(T)` block, so the root of each base type sat in whichever content file claimed it first
(`/atom` in the xenoarch file, `/obj/item` in the robot component file, `/mob/living` in the AI integration file), and every
feature that wanted an entry on a base type had to edit that god block.

## The form

```dm
// code/domains/world_model/atom/atom.dm  (the type's home file): the root
CAPABILITIES(/atom)
	atom_rules(...)

// code/content/xenoarcheaology/effect_master.dm  (the feature's file): a part
CAPABILITIES_PART(/atom, xenoarch)
	owns_one(nameof(artifact_master), /datum/artifact_master)
```

- The root stays the one composition root and lives in the type's home file. A bare `CAPABILITIES(T)` with no entries is a
  valid root (`/datum`: `code/host/datum/capabilities.dm`).
- A part has the same block syntax (indented entries, `section()`s) and holds the same entries as a root. Its header is
  `CAPABILITIES_PART(T, feature)`; `feature` is an identifier. The DM macro is
  `T/proc/__capabilities_part_<feature>()`.
- A feature name is unique across all types: DM declares the part as `T/proc/__capabilities_part_<feature>()` and a subtype may not redeclare a proc its parent declares, so two parts named `hands` on `/mob/living/carbon` and `/mob/living/carbon/human` fail to compile. Name a feature for its type when two types take the same one (`human_hands`, `robot_hands`, `carbon_hands`).
- A part for a type with no root is an error, as are a second part with the same feature on a type, a feature that is not an
  identifier, and (as before) a second root.

## Merge order (deterministic)

For each type `analyze gen declare` writes one `T/declared_entries()`:

1. the root's entries, in the order written;
2. then each part's entries, parts sorted by feature name (ties impossible: duplicates are an error), entries in the order
   written inside a part.

The order does not depend on file paths, include order or the order the files are scanned. Subtypes inherit the merged entries
exactly as before: the table builder compiles one block per type (`entry_block`), and a subtype's block is built over its
parent's. Entries that depend on each other (an `extend()` and the `op()` it addresses, `setup()` steps that read the step
before) stay in one block: move them together or leave them in the root.

## Origins and diagnostics

Every entry already carried `file:line` through `entry_line(line, section)`. A part's entries add the file:
`entry_line(line, section, "path/to/part.dm")`, so the table builder's errors, Explain Type and the static-entry reader name the
part's file and line, not the root's. Analyzer diagnostics (`a var assignment inside the block`, `section ... has no entries`)
point at the part's own file. The generated `declared_entries()` has a `// part <feature> at file:line` comment before each part.

Duplicate or conflicting entries across parts are errors exactly as inside one block, because after the merge they are one block:
the table builder reports a duplicate op key, a second `owns_one` of a var and so on with both origins.

Static entries (`loot()`, `map_resolver()`) of the root and the parts are merged into the type's one row of
`declared_static_blocks()`.

## What reads parts

`sem::decls` reads `CAPABILITIES_PART` as a marker named `CAPABILITIES` with `part = Some(feature)`; the feature is not one of its
arguments. Every consumer that walks the blocks of a type (relations, op keys, handler discovery, UI types, lifeform flags) sees a
part as one more block of the type. Only the generator and the `own_decl` codemod (which adds a var's relation entry to the
type's root) care whether a block is a root.

## Moved roots

The roots of `/atom`, `/atom/movable`, `/obj`, `/obj/item`, `/obj/effect`, `/mob/living`, `/mob/living/carbon`,
`/mob/living/carbon/human`, `/mob/living/silicon/robot`, `/turf/simulated`, `/client` and `/datum` are in their home files, with
feature parts in the feature files (xenoarch, forensics, alt_appearance, lighting, burning, vore, ai, hands, ...).
