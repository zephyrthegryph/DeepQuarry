# Retained session queries

`dmbc query REQUEST.json` returns one JSON object. Add `--jsonl` to emit a
`query_batch` metadata row followed by `resolved_query` answer rows.
This command contacts an **existing compatible daemon**. It never builds,
starts a daemon, retires a daemon, or refreshes sources.

First compile/analyze the same manifest, defines, engine path and bootstrap
configuration through the daemon. Those four fields identify the session.
A busy session rejects queries; retry after its build completes.

An exact discovery request (an empty batch is valid):

```json
{
  "project": "E:/projects/dq-wt/my-worktree/deepquarry.dme",
  "defines": {},
  "engine_template": "E:/dq-cache/native-engine.dmb",
  "bootstrap_catalog": true,
  "expected_revision": null,
  "queries": [],
  "expected_source_revision": null,
  "source_queries": []
}
```

The reply's `revision` is the retained semantic tree's 32-digit hexadecimal
identity. Supply it as `expected_revision` on later requests to reject stale
semantic snapshots. A source edit does **not** refresh that snapshot: build or
analyze first. The revision is semantic identity, not a publication pair ID or
proof that the filesystem is unchanged. The schema is `dm-session-query-v2`.
`source_revision` separately identifies the last admitted frontend source projection;
it changes for body edits and source shifts even when semantic identity stays equal.
`snapshot_outcome` distinguishes `frontend_analyzed`, `analyzed`, `published`, and
`frontend_analyzed_build_failed`. `last_request_outcome` reports the latest request
separately: failure before a frontend is available does not retag the older snapshot.
`publication_pair` contains the exact pair ID only after successful publication
and conventional installation. Compare it to the compile result's `Published.pair.id`
(formatted as 32 hexadecimal digits). It is independent of the source revision:
asset-only edits can publish a different pair with the same source projection.
The field clears when a new request begins or fails.

An output-only session hit does not issue a fresh frontend and leaves source
queries unavailable until a frontend build/analysis runs, while still reporting
the successfully installed `publication_pair`. No outcome certifies current filesystem freshness.

## Python lint callers

First compare the analysis schema row's `semantic_revision` with the query reply's
`revision`. For source joins, also compare its `source_revision`. Reject mismatches;
do not combine rows from different projections.

Discover symbols from the existing `dmbc analyze` JSON-lines export. Do not hash
names independently or use dense tree/member indexes. For a `type` row, the
stable `id` is `type:<16 hex digits>`; convert those digits to a Python integer.
`SymbolId` serializes as an unsigned integer, and `ResolveQuery::Parent` as
`{"Parent": <SymbolId>}`. Python preserves the full 64-bit integer.

```python
import json
from pathlib import Path

rows = [json.loads(line) for line in Path("analysis.jsonl").read_text().splitlines()]
metadata = next(row for row in rows if row.get("row") == "schema")
type_row = next(row for row in rows if row.get("row") == "type")
symbol_id = int(type_row["id"].split(":", 1)[1], 16)
request = json.loads(Path("discovery.json").read_text())
discovery = json.loads(Path("discovery-reply.json").read_text())
if metadata["semantic_revision"] != discovery["revision"]:
    raise ValueError("analysis/query semantic revisions differ; refresh deliberately")
request["expected_revision"] = metadata["semantic_revision"]
request["queries"] = [{"subject": type_row["id"], "query": {"Parent": symbol_id}}]
Path("request.json").write_text(json.dumps(request))
```

Run `dmbc query request.json --jsonl`. Query enums use the existing compiler
`ResolveQuery` serde wire; answers use `dm-resolved-query-v1`. A stale response
is rejected; rediscover only after deliberately updating/rechecking the session.

## Bounds and coverage

- At most 128 combined semantic and source queries and 256 UTF-8 bytes per optional subject.
- Request JSON at most 64 KiB; answer JSON-lines at most 512 KiB.
- A source row may expose at most 1,024 definition-origin spans; deeper provenance fails explicitly.
- Client transport deadline: 20 seconds. No automatic retry or build occurs.
- `complete` is always `false`: this endpoint exposes the retained semantic tree.
  Selected executable references, full macro traces and pinned resource/runtime
  host facts remain outside its coverage.
- `missing`, proven negative answers, and `unsupported` remain distinct. Unknown
  inherited modifiers are exported as `null` plus an explicit unknown status.
- A missing/evicted session fails; run the ordinary build/analysis path before
  querying. The endpoint never creates an empty session to manufacture answers.

## Current source occurrences

After discovering both revisions, send a bounded source selection:

```json
"expected_revision": "<semantic revision from matching analysis schema row>",
"expected_source_revision": "<source revision from matching analysis schema row>",
"source_queries": [{"Occurrence": {"ordinal": 0}}, {"Provenance": {"ordinal": 0}}]
```

`ordinal` is the analysis export's `occurrence` field, or an ordinal discovered
through the occurrence pages below. Both revision pins are
mandatory for source selections. Both typed selections use the same issued occurrence/provenance producer.
Each answer uses `dm-session-source-query-v1`
and contains the issued declaration target, source range, include occurrence,
region and macro definition origin ranges from the existing occurrence table.
Unknown ordinals and stale pins fail the batch; source rows are not silently
omitted. `provenance_complete` remains false because expanded macro traces and
executable node coordinates are not served here. No body parsing occurs.

### Discovering occurrences without another analysis export

An empty query batch discovers the current `revision` and `source_revision`.
Pin both values, then request:

```json
"source_queries": [{"OccurrencesPage": {"start": 0, "limit": 64}}]
```

The single `source_occurrences_page` envelope contains `total`, `returned`,
`next_cursor`, and `items` in exact current occurrence order. Continue with
`next_cursor` until it is null, keeping both revision pins unchanged. A page
limit is 1 through 128; `start == total` returns an empty final page, while a
cursor beyond the roster is rejected. Stale pins require discovery and restart.

`page_complete: true` certifies the requested page range was emitted. The page
and query batch retain `complete: false`; occurrence enumeration does not certify
complete executable resolution or provenance. A response exceeding 512 KiB is
rejected as a whole, so reduce the page limit rather than skipping any ordinal.
Previously captured selected-reference limits still apply independently.

### Previously captured executable references

An explicit `analyze --resolved` request to the retained daemon records bounded
current compiler-selected rows. A subsequent source query can request
`{"SelectedReferences":{"ordinal":42}}`, using a procedure occurrence ordinal
from that same source revision. Both `expected_revision` and
`expected_source_revision` are mandatory. The daemon serves the already issued
rows; it does not parse, resolve, or lower a missing procedure.

At most 256 procedures and 512 KiB of selected JSONL are retained per current
source snapshot. An uncaptured or omitted procedure returns a not-captured error;
run explicit resolved analysis before querying. A new frontend snapshot replaces
these rows. Source shifts invalidate old pins. Coverage remains incomplete:
compiler-selected reference support is partial, and this endpoint does not supply
full macro traces or pinned runtime/resource host facts. This capability adds no
selection traversal to ordinary compile requests.