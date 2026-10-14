# Current procedure identity across repeated declarations

These compile-only controls use the pinned DreamMaker executable recorded in
`receipt.json`. No DreamDaemon execution is involved.

In both declaration orders, `__PROC__` pushes the ID of the body containing it:
body 0 pushes `[38, 0]` and body 1 pushes `[38, 1]`. It does not reference the
final effective body for the owner/name. Formal followed by implicit compiles
without warnings; the reversed order compiles with `no_parent` and
`override_before_def` warnings preserved in the raw log.

The Rust lowering sidecar therefore carries the exact structural procedure
identity, including occurrence. Ordinary call dispatch remains a separate lookup.
The receipt hashes bind the source, raw compiler logs and native binaries.
