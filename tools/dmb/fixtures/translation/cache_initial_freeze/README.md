# Initial and saved receiver selection

These fresh Dream Maker 516.1687 and patched OpenDream outputs distinguish
unguarded frozen receiver reads from safe reads that select the current child.
After a method replaces `OWNER.child`, native unguarded `initial` and `issaved`
can retain the original cached child. Selecting the replacement changes results
when the child subtype has a different default or the field is temporary.

Safe `OWNER.child?.value` forms deliberately select the current child. The
lowerer preserves their setup and supports both Initial and IsSaved. It folds
adjacent pure owner getters into a complete selector, then removes a receiver
prefix only when the entire receiver matches a proven frozen owner.

`tests/cache_initial_freeze.rs` compares 20 complete procedure bodies in ordinary
and debug modes, checks both switch arms, and verifies the distinct default and
temporary-field declarations. The fixtures include fresh-owner, reassignment,
other-receiver, global-call, factory, deep-chain and ordinary-if controls.
No DreamDaemon was run.
