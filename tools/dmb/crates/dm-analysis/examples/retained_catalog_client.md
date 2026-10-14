# Retained catalog clients

This interface queries an already built, compatible daemon session. It does not
start a daemon, compile a project, or create a second semantic model. A missing,
busy, evicted, incompatible or stale session is an error. Do not turn that error
into a negative semantic fact or silently switch compilers.

## Discover and pin

Write a request file with the same project, defines, engine template and bootstrap
configuration used to build the retained session:

```json
{
  "project": "E:/projects/example/comparison.dme",
  "defines": {},
  "engine_template": null,
  "bootstrap_catalog": false,
  "expected_revision": null,
  "queries": [],
  "source_queries": []
}
```

Run `dmbc query REQUEST.json`. Stdout is one `dm-session-query-v2` JSON envelope.
Check its schema and retain its exact 32 hexadecimal character `revision` string.
An empty discovery request returns no catalog rows. Copy that revision into
`expected_revision` for every subsequent page and resolver request. A stale pin
fails; restarting discovery requires discarding the previous traversal and its
dense ordinals.

## Stream a roster

Use one source selector per request, keeping `queries` empty:

```json
"source_queries": [{"SemanticTypesPage": {"start": 0, "limit": 128}}]
```

The other selectors are `SemanticMembersPage` and `SemanticIntrinsicMembersPage`.
All require the semantic revision pin. They do not require a source snapshot pin.
The reply envelope's `jsonl` string contains the page row. Parse it as JSON-lines,
then validate `dm-session-semantic-page-v1`, the expected row kind, exact revision,
requested start/limit, contiguous ordinals and returned count. Follow
`next_cursor`; null means this roster ended. Keep only the current page unless
your application deliberately builds its own compact result index.

`dmbc query REQUEST.json --jsonl` instead emits a `query_batch` header followed by
page rows. The header is not a page and is not the `dm-tree-analysis-v3` header
used by `analyze`. Preserve its coverage and snapshot outcome when consuming this
form. Request files are limited to 64 KiB; pages are limited to 128 rows.

Set explicit limits on pages, total items and elapsed time, and cancel owned
requests when the caller stops. The existing transport uses 20-second timeouts;
these are not a strict whole-traversal deadline. Rust clients can use
`dmbc::daemon::query::semantic_client::visit_catalog`, which implements bounded
one-page traversal and caller cancellation checkpoints over this same transport.

## Meaning and coverage

- Types expose current semantic type nodes and parent links.
- Members expose authored member nodes, definitions and previous override links.
- Intrinsics expose the captured engine inventory, selectors and explicit storage
  proof flags. A missing name spelling is represented by null `name` and
  `name_spelling_known: false`; keep `name_symbol` as its exact selector.
- `intrinsic_inventory_complete: false` means absence from that roster cannot
  establish that an intrinsic does not exist. `hierarchy_certified` is separate.
- Inherited effective members are not expanded into a type-by-member catalog.
  Use parent links and caller-selected ordinary `Resolver` queries through the
  same pinned query endpoint. Preserve known, missing and unsupported answers;
  unsupported is not absence. Exact symbolic IDs must remain hexadecimal strings,
  rather than floating-point JSON numbers.

`page_complete` and a final null cursor certify enumeration of the stated roster,
not complete source or executable analysis. Overall `complete` remains false.
Occurrence/provenance selectors additionally require `expected_source_revision`;
selected-reference results cover only facts already captured by resolved analysis.
Lints requiring unavailable domains must keep their existing implementation.
