# Shared resolved analysis

`dm-analysis` streams JSON-lines from the compiler's issued `ColdFrontend`.
It uses the same declaration model and resolver as compilation; it does not parse
source again or depend on compiler cache internals.

```powershell
# From tools/dmb; defines are explicit target inputs.
cargo run -j1 -p dmbc -- analyze --no-daemon project.dme --workers 2 -DDM_VERSION=516 -DDM_BUILD=1687 > analysis.jsonl
python crates/dm-analysis/examples/list_shared_variables.py analysis.jsonl
```

Stdout contains only JSON-lines. Diagnostics and frontend timings go to stderr.
Analysis excludes procedure lowering, linking, resource loading and publication.

For executable syntax and lexical bindings, add `--bodies` to `analyze`:

```powershell
dmbc analyze project.dme --bodies --workers 2 > bodies.jsonl
```

This uses the compiler's authenticated body parser and current declaration model.
Each parsed body is released after export, so the CLI does not retain every AST.
The additional rows use `dm-typed-body-analysis-v1` and
`dm-lexical-body-analysis-v1`. Lexical bindings cover arguments, local declarations
and their scopes. Nonlocal meanings require resolver queries; selectors and
unsupported call forms remain explicit gaps. Read the binding summary and
`semantic_resolution_complete` before treating reference coverage as complete.
`--bodies` is an analysis option, not a compilation option.

## Versioned contract

The first row is `schema: dm-tree-analysis-v3`. Consumers must reject unsupported
schema versions and inspect its `model`, engine certification and unsupported
domains. Optional engine seed facts distinguish certified hierarchy from source
only inheritance; an intrinsic catalog does not imply decoded intrinsic metadata.

Type and member IDs are structural hexadecimal strings. Member suffixes use the
semantic tree's normalized owner-local override depth, including implicit bodies
that precede formal declarations. A body edit does not renumber declarations.
Meaning fingerprints describe semantic content separately from identity.

`member` rows contain signatures, modifiers, settings and declared/effective
initializers. `occurrence` and `body` rows carry current paths, logical spans,
include context and macro invocation/definition traces. Join `occurrence.target`
to a declaration `id`. Absolute source positions are separate from structural
identity. Macro expansions do not provide a character-level inverse edit map.

`resolved_query` rows use `dm-resolved-query-v1`. The automatic member queries
resolve effective storage, declared types, constants and procedure dispatch.
Their `subject` identifies the declaration being inspected; their answer may
identify an inherited or effective override, rather than that declaration's body.

Answers distinguish `known` (including false presence), `missing`, and
`unsupported`. Never interpret unsupported as absent. IDs/fingerprints are hex
strings; `query_wire` is a JSON-encoded string preserving complete u64/u128 query
values even when the outer consumer uses floating-point JSON numbers. Domain
versions can be null when a resolver cannot certify a domain.

Rust tools can submit other queries with
`tree_export::write_queries_jsonl(symbols, resolver, queries, writer)` and
`AnalysisQuery { subject, query }`. This calls the generic `dm_ir::Resolver`
contract directly and retains negative and unsupported answers. These extra rows
are opt-in; the CLI does not enumerate every possible query.

## Lint migration scope

Declaration documentation, signatures, inheritance, settings and shared-variable
checks can consume this model today. The streaming example lists resolved shared
variables without parsing DM or assuming declaration spelling determines storage.
A consumer may keep its own compact ID/location index when joining rows.

Complete resolved executable reference edges, full resource discovery, opaque
intrinsic metadata, and complete constant evaluation are not exported. Lints requiring those facts
must retain their existing implementation until their required domain is supplied.
Exact source rewriting also needs independent edit-range validation, especially
for macro-expanded declarations. This export is not a complete replacement for
the existing lint engine.
