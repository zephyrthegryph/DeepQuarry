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
