# Native lazy scalar memoization

`memo(key, PROC_REF(compute))` declares a pure, lazy output in a type's
`CAPABILITIES` block. `memo_value(holder, key)` returns it. Null and FALSE are
cached results, not missing entries. Outputs are limited to text, numbers and
null; returning a datum or mutable list fails explicitly.

Generated dependencies bind actual tracked fields, relation members, declared
lookups and nested memo outputs. A read validates the real input snapshot, so
replacement, removal and deletion cannot retain an old result. Memo cells hold
weak producer handles rather than borrowed world objects. Publication inside a
state batch dirties the memo immediately while observer delivery waits for the
completed batch. Computation faults and cycles invalidate the partial result
and unwind evaluation guards.

Asset preparation remains outside the pure computation: it realizes pending
spritesheets and stages real transport, item and ordered child references.
Owned mapping records preserve aliases; child-position records preserve both
order and repeated children. Only URL JSON and the formatted message are cached.
Configuration changes pass through the assets system API. No revision counter
stands in for the real inputs.

Cache-item `hash`, `name` and `ext` are actual tracked inputs, not immutable
constructor dependencies. The six existing constructor assignments use their
registered setters. Superuser SDQL UPDATE retains its existing permission to
bypass ordinary VV restrictions while invoking registered setters; unregistered
fields keep the raw update path. This makes privileged identity edits invalidate
the same real memo dependencies as normal setters.

Verification is pending. The focused selectors are `dq_lazy_memo`,
`dq_asset_memo`, `dq_requirement_protocol_pin` and `dq_conversion_pin`, plus
the lane-ready smoke and incremental appearance checks. This document does not
claim compilation, test results or a lane-ready stamp.

### Strict input and deletion contract

Memo generation accepts actual tracked fields (including registered `SETTER`
fields), declared relations and their collection state, genuine `const` values,
and DM's read-only intrinsic type identity. Ordinary untracked fields are rejected,
even if current writes occur only in constructors. Reflection makes a
constructor-only inference insufficient; no file-path exemption establishes
immutability. Intermediate collection and relation reads obey the same rule.

`QDELETED()` reads have explicit native `lifetime:deleted` metadata. Actual
source identity is bound weakly, and marking `GC_BATCH_DOOMED` invalidates memo
subscribers before any destruction phase runs. Nested input signatures are
validated synchronously without invoking child callbacks. An untaken dependency
cycle produces a stable signature marker; an actual recursive memo computation
still raises a cycle fault.

Warm reads currently revalidate their actual input graph. They do not skip this
check merely because observer delivery has not run. Invalidation during
`state_batch()` remains synchronous while observer publication stays deferred.
