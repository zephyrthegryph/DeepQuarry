# Native procedure-value selection

BYOND516.1687 compile-only receipts, sequential hidden process and60-second limit, no runtime execution. Receipt binds exact source/manifests/native binaries/logs bySHA256 and pinned compiler hash.

`selection.dm` certifies that explicit `/datum/base/proc/callback` refers to formal body returning1, while bare `/datum/base/callback` refers to the implicit override returning2. Both native defaults use tag38 and actual procedure table index, not a class or proc-reference index. Root global and explicit verb literals retain their separate identities. A child field referring to the base literal retains the base formal identity.

Both inherited controls reject `/datum/child/proc/callback`, with and without an implicit child override. Formal literals therefore require an authored formal at the stated owner; inherited presence alone cannot issue that reference.

Current initializer admission supports explicit proc/verb literals with resolver-issued exact source identities. Bare callable initializer paths retain conservative type validation until that separate selection is wired. Runtime literal producer carries a distinct exact identity sidecar; call dispatch retains effective resolution.
