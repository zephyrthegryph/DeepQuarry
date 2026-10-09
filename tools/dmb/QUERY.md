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
  "queries": []
}
```

The reply's `revision` is the retained semantic tree's 32-digit hexadecimal
identity. Supply it as `expected_revision` on later requests to reject stale
semantic snapshots. A source edit does **not** refresh that snapshot: build or
analyze first. The revision is semantic identity, not a publication pair ID or
proof that the filesystem is unchanged.

## Python lint callers

Discover symbols from the existing `dmbc analyze` JSON-lines export. Do not hash
names independently or use dense tree/member indexes. For a `type` row, the
stable `id` is `type:<16 hex digits>`; convert those digits to a Python integer.
`SymbolId` serializes as an unsigned integer, and `ResolveQuery::Parent` as
`{"Parent": <SymbolId>}`. Python preserves the full 64-bit integer.

```python
import json
from pathlib import Path

rows = [json.loads(line) for line in Path("analysis.jsonl").read_text().splitlines()]
type_row = next(row for row in rows if row.get("row") == "type")
symbol_id = int(type_row["id"].split(":", 1)[1], 16)
request = json.loads(Path("discovery.json").read_text())
request["expected_revision"] = json.loads(Path("discovery-reply.json").read_text())["revision"]
request["queries"] = [{"subject": type_row["id"], "query": {"Parent": symbol_id}}]
Path("request.json").write_text(json.dumps(request))
```

Run `dmbc query request.json --jsonl`. Query enums use the existing compiler
`ResolveQuery` serde wire; answers use `dm-resolved-query-v1`. A stale response
is rejected; rediscover only after deliberately updating/rechecking the session.

## Bounds and coverage

- At most 128 queries and 256 UTF-8 bytes per optional subject.
- Request JSON at most 64 KiB; answer JSON-lines at most 512 KiB.
- Client transport deadline: 20 seconds. No automatic retry or build occurs.
- `complete` is always `false`: this endpoint exposes the retained semantic tree.
  Current source occurrences/provenance, selected executable references, and
  pinned resource/runtime host facts are outside this endpoint's coverage.
- `missing`, proven negative answers, and `unsupported` remain distinct. Unknown
  inherited modifiers are exported as `null` plus an explicit unknown status.
- A missing/evicted session fails; run the ordinary build/analysis path before
  querying. The endpoint never creates an empty session to manufacture answers.
