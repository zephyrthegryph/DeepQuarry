# Analysis facts

`Snapshot::from_frontend` accepts an existing declaration index, parser AST and
preprocessed project. It exports canonical declarations and inheritance, exact
authored procedure headers, include origins, and existing diagnostics. It does
not reparse or invent semantic resolution.

JSONL begins with a versioned `snapshot` record and an explicit coverage report.
Each subsequent line is one tagged fact. Signature headers are source facts;
parameter types and defaults are not claimed semantically resolved. Unsupported
parser items or parser diagnostics mark declaration coverage partial. References
start unavailable. The resolution producer supplies canonical resolved targets,
unresolved references and dynamic references through `add_references`, with an
honest coverage level. An export with partial coverage remains useful to tooling
without pretending that missing facts are negative answers.

Use `write_jsonl` for streaming export and `read_jsonl` for version-checked import.
`persist` publishes the full snapshot through `dm-store` under caller-provided
read witnesses. Analysis construction and JSON encoding happen outside the
database lock. Locations use expanded-file ID zero and preprocessing origins;
unmapped source IDs produce no location rather than a fabricated one.

Location indexes are built once per snapshot; each lookup searches line starts
and include-origin boundaries. Imports reject any individual encoded fact larger
than 8 MiB before growing the record buffer beyond that limit.

## Shared native query model

`Coordinator::project_analysis_view(key, source_budget, builtin_image)` returns
an immutable `FrontendView` backed by the native compiler's persisted syntax
fragments and owner recipe DAG. `analysis-jsonl` uses this path. It does not
assemble a whole-project AST or compile output binaries.

`view.items()` yields borrowed `ItemRef` values in source order; use `span()` and
`header_span()` to translate local fragment offsets. `fragment_at(offset)` finds
its content ID. Fragment IDs exclude worktree lineage and absolute positions;
procedure records expose canonical paths and body digests separately.

`view.declarations` supplies canonical owners, fields, procedure occurrences,
inheritance, and override lookup. `resolve_field` and `resolve_procedure` follow
its inheritance model. `view.resolved` queries the native owner model, including
builtin and global field metadata. Its `resolve_value` evaluates a requested
field through the existing cached resolver and returns exact positive/negative
semantic read witnesses. Export does not eagerly evaluate every default.

`Snapshot::from_shared_frontend` exports these shared facts. JSONL schema 2 adds
`fragment`, `procedure_fragment`, `resolved_owner`, and `resolved_field` records;
the reader also accepts schema 1. General expression/reference resolution is
still unavailable, and signatures remain exact source headers with partial
semantic coverage. The adapter does not infer resolved parameter types or
pretend dynamic expressions are constant values.
