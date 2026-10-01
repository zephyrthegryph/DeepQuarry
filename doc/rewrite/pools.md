# Pools

Status: **[in progress]** on `rewrite/f-look` (owner W3). The current `POOL_DECLARE`/`POOL_RESET`
damage-packet pool is **[built]** and described in [lifecycle.md](lifecycle.md). Overview:
[foundation.md](foundation.md).

## 1. What a pool is

A pool recycles a flyweight datum that would otherwise be allocated per event: damage packets,
notices, operation contexts. `/datum/pooled` is the base type.

| API | Meaning |
|---|---|
| `/datum/pooled` | Base. Declares its fields with initial values. |
| `take(type)` / `release()` | Get one from the free list (or allocate) / return it. |
| **Automatic reset** | On release, every field returns to its initial value. Lists allocated in `New()` are kept and emptied rather than reallocated. |
| `reset()` hook | For what field reset cannot express. |
| `pool_max_free` | Cap on the free list per type. |
| `snapshot()` | Copy of the current values for anything that must outlive the release (a log, a queued notice). |
| **Poison** | Always on in test builds: a released datum's fields are poisoned so use-after-release fails loudly. |
| **Lint** | Every `take` reaches a `release`, and no reference to a pooled datum is stored past the handler. |

## 2. Rules

- A pooled datum is valid only for the duration of the call that received it. Handlers that need
  data later copy it or call `snapshot()`.
- Do not hold a pooled datum in a var, list or timer. The `ownership()`/relations misuse that did
  so for damage packets is removed.
- Damage packets are converted to `/datum/pooled`; see [damage.md](damage.md). Notices
  ([reactions.md](reactions.md)) and operation contexts ([operations_and_actions.md](operations_and_actions.md))
  use the same base.
- `POOL_DECLARE`/`POOL_RESET` remain as wrappers until every pool is converted.
