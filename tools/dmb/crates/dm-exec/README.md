# dm-exec

`BuildExecutor` is the execution boundary for one compiler request. Construct it
once with the requested worker count and pass `&BuildExecutor` through scanning,
preprocessing, declaration parsing, preparation, lowering and linking. Repeated
stages use the same bounded workers; separate requests/worktrees own separate
pools. No hardware cap or global Rayon registry changes the requested count.

Use `scope` (or `scope_in_place`) for borrowed jobs. The scope body stays on the
calling thread and all spawned jobs complete before it returns, even if one
panics. `install` makes Rayon iterators and joins use this executor. Keep ordered
result/error aggregation in the stage; scheduling order is not output order.

Drop or consume `shutdown()` **before** finishing a profile. Unlike ordinary
Rayon pool drop, executor drop joins its OS threads after signalling shutdown.
The executor is not cloneable: its owner cannot accidentally become a worker
that would have to join itself. Early-return and panic paths get the same join.

Every worker records one direct-clock lifetime interval inside its thread.
`dm-profile` adds this interval to participating-thread coverage, with the same
uncertainty calculation as existing stages. It never adds lifetime CPU to stage
exclusive totals or folded stacks. Coverage takes a union, so a nested stage is
not counted twice; worker scheduling overhead is covered while stage attribution
remains independently measured. Lifetime observers do not claim allocation or
private-memory attribution.
