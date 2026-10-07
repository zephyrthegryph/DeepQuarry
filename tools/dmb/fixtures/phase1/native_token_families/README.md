# Allocation-default token families

Compile-only controls captured with BYOND 516.1687. `receipt.json` binds every
source, manifest, native binary and raw compile log by SHA-256. No DreamDaemon
was run. These are default-record and equality-partition observations, not a
claim about execution scheduling.

| Form | Global / procedure static | Class field | Const in any of these scopes |
| --- | --- | --- | --- |
| `list(1, 2)` | kind 62 | kind 62 | rejected |
| `alist(1 = 2)` | kind 62 | kind 62 | rejected |
| `regex("a")` | kind 0, value 0 | rejected | rejected |
| `typesof(/datum/token_target)` | kind 0, value 0 | rejected | rejected |

The ordinary list and alist controls each share one token across two globals,
two fields and two procedure statics. `alist-identity` proves that an identifier
association key and the equivalent text key share a token, and folded numeric
keys share a token with their literal values. Empty alist and empty list are
distinct, as are equivalent alist and list associations. Repeated associations
and unrelated runtime arguments have no additional proof in this cohort.

Class regex/typesof controls report `expected a constant expression`. All twelve
const controls report `constant initializer required`. The positive global and
static regex/typesof binary controls retain null defaults; they must not acquire
kind-62 markers merely because they allocate at runtime.
