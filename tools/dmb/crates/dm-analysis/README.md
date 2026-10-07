# Shared source analysis

`dm-analysis` streams JSON-lines directly from `dm-tree::frontend::ColdFrontend`.
It has no dependency on the historical compiler, Salsa or its cache/proof layers.

The current command is:

```powershell
cargo run -j1 -p dmbc -- analyze --no-daemon project.dme --workers 2 -DDM_VERSION=516 -DDM_BUILD=1687 > analysis.jsonl
```

Run from `tools/dmb`, or pass a project path relative to the current directory.
Defines are explicit inputs; the reusable frontend does not infer the target
engine. JSON-lines go to stdout; diagnostics and frontend stage timings go to
stderr. These timings exclude lowering, linking, resource loading and publication.

## Contract

- The first row names the versioned schema and model limitations.
- Type/member rows use structural identities; values, signatures and settings
  have a separate meaning fingerprint. Identities are hexadecimal strings.
- Semantic expression tokens retain spelling, stable token kinds and significant
  operator adjacency. Source whitespace and absolute positions do not enter
  those rows.
- Occurrence/body rows describe current source paths, logical source spans,
  include context and actual macro invocation/definition traces. Character-level
  inverse macro substitution is not available.
- Declaration rows expose declared and effective defaults separately. Scalar
  literal values retain exact numeric bits and string bytes; general constant
  evaluation is unfinished.

This is a source-declaration model. Engine hierarchy/inventory certification,
executable reference resolution, resource discovery and full compiler integration
remain unfinished. Consumers must read the schema limitations before treating
source-only inheritance or an unsupported query as a complete runtime answer.
The API is ready for experiments with declaration documentation and source-based
checks; it is not yet a complete replacement for the existing lint engine.
