# Six registered Git worktree transport contract

Source-only fixture; not yet executed. This is a tiny protocol/output isolation gate, not real DeepQuarry six-worktree acceptance or a performance measurement.

Run `python run.py --native EXE --native-sha256 SHA --template TEMPLATE --template-sha256 SHA` after coordinating execution. Evidence and the mini repository live in a new owned E:/dq-cache directory; six registered worktrees live only under E:/projects/dq-wt. The fixture initializes its own mini repository, registers six detached worktrees without changing main history, and removes only its own registrations after reaping children. Receipts/logs/output evidence remain.

Serial fresh native oracles precede daemon startup. Two concurrent clients share one owned daemon with a total worker cap of two. Initial and asymmetric revisions compare each root's authenticated DMB/RSC output pair: root zero edits a body, root one adds a field/proc, four roots remain unchanged. Source/tool hashes and per-command records are preserved. Aggregate Job cap is 4 GiB, soft daemon threshold 2 GiB, overall 240 seconds (40 reserved for reaping/removing owned registrations) and each child 30 seconds. Eviction is permitted; six graphs need not remain resident. No DreamDaemon or BYOND runtime execution occurs.
